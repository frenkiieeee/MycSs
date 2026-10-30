import Foundation

/// Fetches lyrics from the NetEase Cloud Music public API.
///
/// NetEase is used only as a source of *true per-word timing*: its `yrc` format
/// gives every word its own start and duration, which is what makes the karaoke
/// highlight land exactly on the voice.
///
/// Two caveats, both verified against the live service:
///
/// - **Not every song has a `yrc`.** "Come Back to Earth" has one; "FANTASMA |
///   AVC" only has line-level `lrc`. So this is an improvement, not a
///   guarantee.
/// - **The search can return unrelated songs** when it is queried repeatedly.
///   Every candidate is therefore validated on title *and* duration before use.
///
/// This is an unofficial, undocumented endpoint. It is used as a best-effort
/// fallback: if it is unreachable or returns something odd, the app falls back
/// to LRCLIB's line-level lyrics.
enum NetEase {

    private struct Song: Decodable {
        let id: Int
        let name: String
        let duration: Double
        let artists: [Artist]

        struct Artist: Decodable {
            let name: String
        }
    }

    private struct SearchResponse: Decodable {
        let result: SearchResult?

        struct SearchResult: Decodable {
            let songs: [Song]
        }
    }

    private struct LyricResponse: Decodable {
        let yrc: YrcEntry?
        let lrc: YrcEntry?

        struct YrcEntry: Decodable {
            let lyric: String
        }
    }

    // MARK: - Fetching

    /// Fetches lyrics with per-word timing for the playing track.
    static func fetch(for nowPlaying: NowPlaying) async -> Lyrics? {
        guard let songID = await searchSongID(for: nowPlaying) else { return nil }
        return await fetchLyrics(songID: songID, for: nowPlaying)
    }

    // MARK: - Search

    private static func searchSongID(for nowPlaying: NowPlaying) async -> Int? {
        let cleanTitle = cleanedTitle(nowPlaying.title)
        let artist = primaryArtist(nowPlaying.artist)

        // Most specific first, then progressively looser. The title decorations
        // that Spotify carries ("(feat. X)", "- Remastered 2011") derail the
        // search, so the title is cleaned before querying.
        let queries = [
            "\(cleanTitle) \(artist)",
            cleanTitle,
            "\(nowPlaying.title) \(nowPlaying.artist)",
        ]

        for query in queries {
            guard let url = searchURL(for: query) else { continue }
            guard let data = await HTTPCache.shared.data(for: url, headers: searchHeaders),
                  let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
                  let songs = response.result?.songs, !songs.isEmpty
            else { continue }

            if let match = pick(songs, for: nowPlaying, cleanTitle: cleanTitle) {
                Log.line("netease: matched '\(match.name)' (id \(match.id)) via '\(query)'")
                return match.id
            }
        }

        Log.line("netease: no acceptable match for '\(cleanTitle)'")
        return nil
    }

    private static func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://music.163.com/api/search/get?type=1&limit=10&offset=0&s=\(encoded)")
        else { return nil }
        return url
    }

    private static var searchHeaders: [String: String] {
        [
            "Referer": "https://music.163.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
        ]
    }

    /// Accepts a candidate only when the title matches and the length is close.
    private static func pick(_ songs: [Song], for nowPlaying: NowPlaying, cleanTitle: String) -> Song? {
        let want = LRCLib.normalise(cleanTitle)
        guard !want.isEmpty else { return nil }

        let titleMatches = songs.filter { song in
            let got = LRCLib.normalise(song.name)
            return got == want || got.contains(want) || want.contains(got)
        }
        guard !titleMatches.isEmpty else { return nil }

        let target = nowPlaying.durationSec * 1000
        guard target > 0 else { return titleMatches.first }

        let sorted = titleMatches.sorted { abs($0.duration - target) < abs($1.duration - target) }
        let best = sorted[0]

        // A live cut or an edit shares the title but not the length.
        if abs(best.duration - target) <= 20_000 { return best }

        // At a track switch the player can report the new title with the
        // previous track's duration, so an exact title match is still trusted.
        if let exact = titleMatches.first(where: { LRCLib.normalise($0.name) == want }) {
            Log.line("netease: matched on title only (duration disagreed)")
            return exact
        }
        return nil
    }

    // MARK: - Lyrics

    private static func fetchLyrics(songID: Int, for nowPlaying: NowPlaying) async -> Lyrics? {
        guard let url = URL(string: "https://music.163.com/api/song/lyric/v1?id=\(songID)&lv=1&yv=1&tv=1&cp=false")
        else { return nil }

        guard let data = await HTTPCache.shared.data(for: url, headers: searchHeaders),
              let response = try? JSONDecoder().decode(LyricResponse.self, from: data)
        else {
            Log.line("netease: lyric fetch failed")
            return nil
        }

        // Prefer yrc: it is the one with real per-word timing.
        if let yrc = response.yrc?.lyric, !yrc.isEmpty {
            var lines = LyricsParser.parseYRC(yrc)
            lines = LyricsParser.filteringCredits(lines)
            if !lines.isEmpty {
                Log.line("netease: \(lines.count) lines with real word timings")
                return Lyrics(
                    lines: lines,
                    duration: nowPlaying.durationSec,
                    source: .netease,
                    wordTimingQuality: .real
                )
            }
        }

        // Fall back to line-level if there is no yrc for this song.
        if let lrc = response.lrc?.lyric, !lrc.isEmpty {
            var lines = LyricsParser.parseLRC(lrc)
            lines = LyricsParser.filteringCredits(lines)
            if !lines.isEmpty {
                lines = WordInterpolator.interpolate(lines, weighting: AppSettings.shared.wordTiming)
                Log.line("netease: \(lines.count) lines, no yrc, interpolated word timings")
                return Lyrics(
                    lines: lines,
                    duration: nowPlaying.durationSec,
                    source: .netease,
                    wordTimingQuality: .interpolated
                )
            }
        }

        Log.line("netease: nothing usable for song \(songID)")
        return nil
    }

    // MARK: - Title cleaning

    /// Strips the decorations that derail the search.
    static func cleanedTitle(_ raw: String) -> String {
        var title = raw
        let patterns = [
            #"\s*[\(\[][^)\]]*\b(feat\.?|ft\.?|with)\b[^)\]]*[\)\]]"#,
            #"\s+-\s+.*$"#,
        ]
        for pattern in patterns {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// The first credited artist only ("A, B & C" becomes "A").
    static func primaryArtist(_ raw: String) -> String {
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: ",&"))
        let first = parts.first ?? raw
        return first.replacingOccurrences(of: #"\b(feat\.?|ft\.?|with)\b.*$"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
    }
}
