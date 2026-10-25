import Foundation

/// Fetches lyrics from LRCLIB (https://lrclib.net).
///
/// LRCLIB is a free, open, key-less service. Its coverage is good and its
/// timings are line-level: every line has a start time, but the words inside a
/// line do not. `WordInterpolator` fills those in.
enum LRCLib {

    /// One candidate returned by the service.
    struct Candidate {
        var trackName: String
        var artistName: String
        var albumName: String
        var duration: TimeInterval?
        var syncedLyrics: String?
        var plainLyrics: String?
    }

    /// Fetches the lyrics for a track, preferring an exact metadata match and
    /// falling back to a fuzzy search.
    ///
    /// - Parameter nowPlaying: the track as Spotify reports it.
    /// - Returns: the parsed lyrics, or `nil` when nothing matched.
    static func fetch(for nowPlaying: NowPlaying) async -> Lyrics? {
        let exact = await fetchExact(for: nowPlaying)
        if let exact { return exact }

        Log.line("lrclib: exact match failed, trying search")
        return await fetchSearch(for: nowPlaying)
    }

    // MARK: - Exact match

    private static func fetchExact(for nowPlaying: NowPlaying) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: nowPlaying.artist),
            URLQueryItem(name: "track_name", value: nowPlaying.title),
            URLQueryItem(name: "album_name", value: nowPlaying.album),
            URLQueryItem(name: "duration", value: String(Int(nowPlaying.durationSec.rounded()))),
        ]
        guard let url = components.url else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = object["syncedLyrics"] as? String,
              !synced.isEmpty
        else {
            Log.line("lrclib: no exact match")
            return nil
        }

        let candidate = Candidate(
            trackName: object["trackName"] as? String ?? nowPlaying.title,
            artistName: object["artistName"] as? String ?? nowPlaying.artist,
            albumName: object["albumName"] as? String ?? nowPlaying.album,
            duration: object["duration"] as? Double,
            syncedLyrics: synced,
            plainLyrics: object["plainLyrics"] as? String
        )

        guard matches(candidate, nowPlaying: nowPlaying) else {
            Log.line("lrclib: exact match rejected by validation")
            return nil
        }

        return build(from: candidate)
    }

    // MARK: - Fuzzy search

    private static func fetchSearch(for nowPlaying: NowPlaying) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: nowPlaying.title),
            URLQueryItem(name: "artist_name", value: nowPlaying.artist),
        ]
        guard let url = components.url else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            Log.line("lrclib: search failed")
            return nil
        }

        let candidates = objects.compactMap { object -> Candidate? in
            guard let synced = object["syncedLyrics"] as? String, !synced.isEmpty else { return nil }
            return Candidate(
                trackName: object["trackName"] as? String ?? "",
                artistName: object["artistName"] as? String ?? "",
                albumName: object["albumName"] as? String ?? "",
                duration: object["duration"] as? Double,
                syncedLyrics: synced,
                plainLyrics: object["plainLyrics"] as? String
            )
        }

        guard let best = pick(candidates, for: nowPlaying) else {
            Log.line("lrclib: no acceptable match in search results")
            return nil
        }

        Log.line("lrclib: matched '\(best.trackName)' by '\(best.artistName)'")
        return build(from: best)
    }

    // MARK: - Matching

    /// Chooses the candidate whose title matches and whose duration is closest.
    ///
    /// Showing the lyrics of a different song is worse than showing nothing, so
    /// a candidate has to satisfy both checks.
    private static func pick(_ candidates: [Candidate], for nowPlaying: NowPlaying) -> Candidate? {
        let wantTitle = normalise(nowPlaying.title)
        let wantArtist = normalise(nowPlaying.artist)
        guard !wantTitle.isEmpty else { return nil }

        var titleMatches: [Candidate] = []
        for candidate in candidates {
            let gotTitle = normalise(candidate.trackName)
            let gotArtist = normalise(candidate.artistName)
            let titleOk = gotTitle == wantTitle
                || gotTitle.contains(wantTitle)
                || wantTitle.contains(gotTitle)
            let artistOk = wantArtist.isEmpty
                || gotArtist.isEmpty
                || gotArtist == wantArtist
                || gotArtist.contains(wantArtist)
                || wantArtist.contains(gotArtist)
            if titleOk && artistOk { titleMatches.append(candidate) }
        }

        guard !titleMatches.isEmpty else { return nil }

        // Prefer the closest duration: live cuts and edits share the title but
        // not the length.
        let target = nowPlaying.durationSec
        guard target > 0 else { return titleMatches.first }

        let sorted = titleMatches.sorted { lhs, rhs in
            let left = lhs.duration.map { abs($0 - target) } ?? .greatestFiniteMagnitude
            let right = rhs.duration.map { abs($0 - target) } ?? .greatestFiniteMagnitude
            return left < right
        }
        return sorted.first
    }

    /// Validates a candidate against the playing track.
    private static func matches(_ candidate: Candidate, nowPlaying: NowPlaying) -> Bool {
        let gotTitle = normalise(candidate.trackName)
        let wantTitle = normalise(nowPlaying.title)
        guard !wantTitle.isEmpty else { return false }
        guard gotTitle == wantTitle || gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) else {
            return false
        }

        // The duration must be close. At the moment a track changes, the player
        // can report the new title with the previous track's duration, so a title
        // match is trusted even when the length disagrees.
        if let duration = candidate.duration, nowPlaying.durationSec > 0 {
            let difference = abs(duration - nowPlaying.durationSec)
            if difference > 20 { return false }
        }
        return true
    }

    // MARK: - Building

    private static func build(from candidate: Candidate) -> Lyrics? {
        guard let synced = candidate.syncedLyrics else { return nil }
        var lines = LyricsParser.parseLRC(synced)
        lines = LyricsParser.filteringCredits(lines)
        guard !lines.isEmpty else { return nil }

        lines = WordInterpolator.interpolate(lines)

        Log.line("lrclib: \(lines.count) lines, interpolated word timings")
        return Lyrics(
            lines: lines,
            duration: candidate.duration ?? 0,
            source: .lrclib,
            wordTimingQuality: .interpolated
        )
    }

    /// Lower-cased, accent- and punctuation-insensitive form for comparisons.
    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
