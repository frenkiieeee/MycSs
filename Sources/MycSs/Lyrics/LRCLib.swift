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

    /// Fetches the lyrics for a track.
    ///
    /// Several strategies are tried in order, because no single one of them
    /// covers everything:
    ///
    /// 1. An exact lookup with the full metadata (title, artist, album, duration).
    /// 2. The same lookup without the album: Spotify and LRCLIB disagree about
    ///    album names often enough that requiring them loses real matches.
    /// 3. A search by title *and* artist.
    /// 4. A search by title alone, validated against the artist and the duration.
    ///
    /// - Parameter nowPlaying: the track as Spotify reports it.
    /// - Returns: the parsed lyrics, or `nil` when nothing matched.
    static func fetch(for nowPlaying: NowPlaying) async -> Lyrics? {
        // The three lookups are independent, so they are asked at the same
        // time.
        //
        // Waiting for them one after the other added seconds to every song:
        // the two exact lookups have to fail before the search even starts,
        // and LRCLIB is often slow to answer or overloaded (503), so each of
        // those rounds costs more than a second.
        await withTaskGroup(of: Lyrics?.self) { group in
            group.addTask { await fetchExact(for: nowPlaying, includeAlbum: true) }
            group.addTask { await fetchExact(for: nowPlaying, includeAlbum: false) }
            group.addTask { await fetchSearch(for: nowPlaying, includeArtist: true) }

            // The first answer that passes the validation is used: the
            // candidates are checked against the title, the artist and the
            // length of the song, so a wrong song is rejected whoever answers.
            for await result in group {
                if let result { return result }
            }

            // Nothing found. The search without the artist is the last resort:
            // it returns many songs with the same title, and the validation is
            // stricter with it.
            return await fetchSearch(for: nowPlaying, includeArtist: false)
        }
    }

    // MARK: - Exact match

    private static func fetchExact(for nowPlaying: NowPlaying, includeAlbum: Bool) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: nowPlaying.artist),
            URLQueryItem(name: "track_name", value: nowPlaying.title),
        ]
        if includeAlbum {
            items.append(URLQueryItem(name: "album_name", value: nowPlaying.album))
        }
        if nowPlaying.durationSec > 0 {
            items.append(URLQueryItem(
                name: "duration",
                value: String(Int(nowPlaying.durationSec.rounded()))
            ))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = object["syncedLyrics"] as? String,
              !synced.isEmpty
        else {
            Log.line("lrclib: no exact match (album: \(includeAlbum))")
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

    /// Searches for the lyrics.
    ///
    /// - Parameter includeArtist: whether to narrow the search by artist. When
    ///   it is off, the results contain many songs with the same title, so the
    ///   artist and the duration have to be checked more strictly.
    private static func fetchSearch(for nowPlaying: NowPlaying, includeArtist: Bool) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var items = [URLQueryItem(name: "track_name", value: nowPlaying.title)]
        if includeArtist {
            items.append(URLQueryItem(name: "artist_name", value: nowPlaying.artist))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            Log.line("lrclib: search failed (artist: \(includeArtist))")
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

        guard let best = pick(candidates, for: nowPlaying, strict: !includeArtist) else {
            Log.line("lrclib: no acceptable match in search results (artist: \(includeArtist))")
            return nil
        }

        Log.line("lrclib: matched '\(best.trackName)' by '\(best.artistName)'")
        return build(from: best)
    }

    // MARK: - Matching

    /// Chooses the candidate whose title matches and whose duration is closest.
    ///
    /// Showing the lyrics of a different song is worse than showing nothing, so
    /// a candidate has to satisfy the checks below.
    ///
    /// - Parameter strict: when the search was made by title alone, the artist
    ///   has to match as well — the results contain many different songs that
    ///   share the title.
    private static func pick(
        _ candidates: [Candidate],
        for nowPlaying: NowPlaying,
        strict: Bool = false
    ) -> Candidate? {
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
            guard titleOk else { continue }
            // In the strict case the artist has to be a real match, not a
            // substring: "Danny Ocean" must not match "Danny Ocean Trio".
            if strict, wantArtist.isEmpty || gotArtist.isEmpty {
                continue
            }
            if strict {
                let artistMatches = gotArtist == wantArtist
                    || gotArtist.contains(wantArtist)
                    || wantArtist.contains(gotArtist)
                guard artistMatches else { continue }
            }
            titleMatches.append(candidate)
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

        lines = WordInterpolator.interpolate(lines, weighting: AppSettings.shared.wordTiming)

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
