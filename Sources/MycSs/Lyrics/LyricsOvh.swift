import Foundation

/// A last-resort lyric source: `lyrics.ovh`.
///
/// **What it is worth**: it returns plain lyrics with no timing at all. It is
/// used only when the sources that carry timing have nothing, so that the screen
/// shows *something* instead of "no lyrics available".
///
/// **How the timing is added**: the lines are spread over the track using the
/// song's own pace, which is what `WordInterpolator` does for the other sources
/// too. The highlight will drift, but it will be there.
enum LyricsOvh {

    /// Fetches plain lyrics for a track.
    static func fetch(for nowPlaying: NowPlaying) async -> Lyrics? {
        guard !nowPlaying.title.isEmpty, !nowPlaying.artist.isEmpty else { return nil }

        // The service wants the plain artist and title, without the decorations
        // Spotify adds.
        let artist = primaryArtist(nowPlaying.artist)
        let title = cleanedTitle(nowPlaying.title)

        guard let url = makeURL(artist: artist, title: title) else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = object["lyrics"] as? String,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Log.line("lyrics.ovh: nothing for '\(title)'")
            return nil
        }

        var lines = LyricsParser.parsePlainLyrics(body)
        lines = LyricsParser.filteringCredits(lines)
        guard !lines.isEmpty else { return nil }

        // Spread the lines over the length of the song so the highlight has
        // something to follow.
        lines = LyricsParser.distributing(lines, over: nowPlaying.durationSec)
        lines = WordInterpolator.interpolate(lines)

        Log.line("lyrics.ovh: \(lines.count) plain lines, timings estimated")
        return Lyrics(
            lines: lines,
            duration: nowPlaying.durationSec,
            source: .lyricsOvh,
            wordTimingQuality: .interpolated
        )
    }

    private static func makeURL(artist: String, title: String) -> URL? {
        var components = URLComponents(string: "https://api.lyrics.ovh/v1")
        components?.path = "/v1/\(artist)/\(title)"
        return components?.url
    }

    /// The first credited artist only.
    private static func primaryArtist(_ raw: String) -> String {
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: ",&"))
        let first = parts.first ?? raw
        return first.replacingOccurrences(of: #"\b(feat\.?|ft\.?|with)\b.*$"#, with: "",
                                          options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
    }

    /// Removes the decorations that break the lookup.
    private static func cleanedTitle(_ raw: String) -> String {
        var title = raw
        for pattern in [
            #"\s*[\(\[][^)\]]*\b(feat\.?|ft\.?|with)\b[^)\]]*[\)\]]"#,
            #"\s+-\s+.*$"#,
        ] {
            title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return title.trimmingCharacters(in: .whitespaces)
    }
}
