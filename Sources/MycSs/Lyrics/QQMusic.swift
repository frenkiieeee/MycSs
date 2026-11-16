import Foundation

/// Fetches lyrics from QQ Music's public web API.
///
/// It is the **third source**, asked only when LRCLIB and NetEase both come back
/// empty (see `LyricsProvider`). Its strength is catalogue: a lot of regional and
/// Asian releases, and many Western ones, that the other two do not have. Its
/// lyrics are line-level, so the word timing is interpolated like LRCLIB's.
///
/// Like NetEase it is an undocumented endpoint used best-effort: if it is
/// unreachable or answers something odd, the result is nil and nothing breaks.
/// Every candidate is checked against title, artist and length, because showing
/// another song's lyrics is worse than showing none.
enum QQMusic {

    private struct Song {
        let mid: String
        let name: String
        let singers: [String]
        let seconds: Double
    }

    private static let headers: [String: String] = [
        "Referer": "https://y.qq.com/",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
    ]

    static func fetch(for nowPlaying: NowPlaying) async -> Lyrics? {
        guard let song = await search(for: nowPlaying) else { return nil }
        return await fetchLyrics(of: song, for: nowPlaying)
    }

    // MARK: - Search

    private static func search(for nowPlaying: NowPlaying) async -> Song? {
        let title = NetEase.cleanedTitle(nowPlaying.title)
        let artist = NetEase.primaryArtist(nowPlaying.artist)
        guard !title.isEmpty else { return nil }

        // With the artist first; the title alone as a second try.
        for query in ["\(title) \(artist)", title] {
            guard let encoded = query.trimmingCharacters(in: .whitespaces)
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
                    + "?w=\(encoded)&format=json&n=10&p=1&t=0&aggr=1&cr=1&catZhida=1&flag_qc=0"),
                  let data = await HTTPCache.shared.data(for: url, headers: headers),
                  let songs = parseSongs(data)
            else { continue }

            if let match = pick(songs, for: nowPlaying, title: title, artist: artist) {
                Log.line("qqmusic: matched '\(match.name)' (\(match.mid)) via '\(query)'")
                return match
            }
        }
        Log.line("qqmusic: no acceptable match for '\(title)'")
        return nil
    }

    private static func parseSongs(_ data: Data) -> [Song]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let container = root["data"] as? [String: Any],
              let song = container["song"] as? [String: Any],
              let list = song["list"] as? [[String: Any]]
        else { return nil }

        return list.compactMap { item in
            guard let mid = item["songmid"] as? String,
                  let name = item["songname"] as? String
            else { return nil }
            let singers = (item["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let seconds = (item["interval"] as? Double) ?? Double(item["interval"] as? Int ?? 0)
            return Song(mid: mid, name: name, singers: singers, seconds: seconds)
        }
    }

    /// Words that mark a different recording of the same title. They are only
    /// accepted when the playing track says the same thing.
    private static let variantMarkers = ["instrumental", "karaoke", "live", "remix", "acoustic", "cover"]

    private static func pick(_ songs: [Song], for nowPlaying: NowPlaying, title: String, artist: String) -> Song? {
        let wantTitle = LRCLib.normalise(title)
        let wantArtist = LRCLib.normalise(artist)
        let playing = nowPlaying.title.lowercased()
        guard !wantTitle.isEmpty else { return nil }

        let candidates = songs.filter { song in
            let gotTitle = LRCLib.normalise(NetEase.cleanedTitle(song.name))
            guard gotTitle == wantTitle else { return false }

            // "Blinding Lights (Instrumental)" is not "Blinding Lights".
            let lowerName = song.name.lowercased()
            for marker in variantMarkers
            where lowerName.contains(marker) && !playing.contains(marker) {
                return false
            }

            // The artist has to be one of the credited ones.
            if !wantArtist.isEmpty {
                let artistOk = song.singers.contains { singer in
                    let got = LRCLib.normalise(singer)
                    return !got.isEmpty && (got == wantArtist || got.contains(wantArtist) || wantArtist.contains(got))
                }
                guard artistOk else { return false }
            }
            return true
        }
        guard !candidates.isEmpty else { return nil }

        let target = nowPlaying.durationSec
        guard target > 0 else { return candidates.first }
        let best = candidates.min { abs($0.seconds - target) < abs($1.seconds - target) }!
        return abs(best.seconds - target) <= 20 ? best : nil
    }

    // MARK: - Lyrics

    private static func fetchLyrics(of song: Song, for nowPlaying: NowPlaying) async -> Lyrics? {
        guard let url = URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
                + "?songmid=\(song.mid)&format=json&nobase64=0&g_tk=5381"),
              let data = await HTTPCache.shared.data(for: url, headers: headers),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let encoded = root["lyric"] as? String,
              let decoded = Data(base64Encoded: encoded),
              let text = String(data: decoded, encoding: .utf8),
              !text.isEmpty
        else {
            Log.line("qqmusic: lyric fetch failed for \(song.mid)")
            return nil
        }

        // An instrumental is announced in the lyric itself.
        if text.contains("纯音乐") || text.contains("此歌曲为没有填词的纯音乐") {
            Log.line("qqmusic: instrumental, no lyrics")
            return nil
        }

        var lines = LyricsParser.filteringCredits(LyricsParser.parseLRC(text))

        // The first line is usually "Title - Artist", which is not a lyric.
        if let first = lines.first,
           first.text.contains(" - "),
           LRCLib.normalise(first.text).contains(LRCLib.normalise(NetEase.cleanedTitle(nowPlaying.title))) {
            lines.removeFirst()
        }
        guard lines.count >= 3 else { return nil }

        lines = WordInterpolator.interpolate(lines, weighting: AppSettings.shared.wordTiming)
        Log.line("qqmusic: \(lines.count) lines, interpolated word timings")
        return Lyrics(
            lines: lines,
            duration: song.seconds,
            source: .qqmusic,
            wordTimingQuality: .interpolated
        )
    }
}
