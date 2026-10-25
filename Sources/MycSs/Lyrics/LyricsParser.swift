import Foundation

/// Parses timed lyrics into the app's own model.
///
/// Two formats are supported:
///
/// **LRC** (LRCLIB) — one timestamp per line:
/// ```
/// [00:12.34] Some lyrics here
/// ```
///
/// **yrc** (NetEase) — one timestamp per line *plus* a timestamp per word:
/// ```
/// [0,5040](0,420,0)My (420,960,0)regrets (1380,360,0)look
/// ```
/// where the line header is `[lineStartMs,lineDurationMs]` and each word is
/// `(offsetMs,durationMs,0)` with the offset relative to the line start.
///
/// yrc files also open with JSON credit lines such as
/// `{"t":-1000,"c":[{"tx":"作词: "},{"tx":"Jon Brion"}]}` — production credits,
/// not lyrics. They are dropped.
enum LyricsParser {

    // MARK: - LRC

    /// Parses LRC text into lines with line-level timing.
    static func parseLRC(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        for rawLine in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine)
            let stamps = lrcTimestamps(in: line)
            guard !stamps.isEmpty else { continue }

            // The text is whatever follows the last timestamp on the line.
            let textStart = line.range(of: "]", options: .backwards)?.upperBound
                ?? line.startIndex
            let text = String(line[textStart...])
                .trimmingCharacters(in: .whitespaces)

            // A line can carry several timestamps (a repeated chorus); each one
            // becomes its own line.
            for stamp in stamps {
                lines.append(LyricLine(
                    startTime: stamp,
                    endTime: stamp,
                    text: text,
                    words: []
                ))
            }
        }

        return finalize(lines)
    }

    /// Extracts every `[mm:ss.xx]` timestamp on a line, in seconds.
    private static func lrcTimestamps(in line: String) -> [TimeInterval] {
        var result: [TimeInterval] = []
        let pattern = #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let ns = line as NSString
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match,
                  let minRange = Range(match.range(at: 1), in: line),
                  let secRange = Range(match.range(at: 2), in: line)
            else { return }

            let minutes = Double(line[minRange]) ?? 0
            let seconds = Double(line[secRange]) ?? 0

            var fraction = 0.0
            if match.range(at: 3).location != NSNotFound,
               let fracRange = Range(match.range(at: 3), in: line) {
                let text = String(line[fracRange])
                // ".5" means half a second, ".05" means fifty milliseconds.
                fraction = (Double(text) ?? 0) / pow(10, Double(text.count))
            }
            result.append(minutes * 60 + seconds + fraction)
        }
        return result
    }

    // MARK: - yrc

    /// Parses yrc text into lines with per-word timing.
    static func parseYRC(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []

        for rawLine in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // JSON credit lines: production credits, not lyrics.
            if line.hasPrefix("{") { continue }

            guard let lineHeader = parseYRCHeader(line) else { continue }
            let (lineStart, lineDuration) = lineHeader

            let words = parseYRCWords(line)
            let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            lines.append(LyricLine(
                startTime: lineStart,
                endTime: lineStart + lineDuration,
                text: text,
                words: words
            ))
        }

        return finalize(lines)
    }

    /// Parses the `[startMs,durationMs]` header of a yrc line.
    private static func parseYRCHeader(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard line.hasPrefix("["),
              let close = line.firstIndex(of: "]")
        else { return nil }
        let body = line[line.index(after: line.startIndex)..<close]
        let parts = body.split(separator: ",")
        guard parts.count >= 2,
              let start = Double(parts[0]),
              let duration = Double(parts[1])
        else { return nil }
        return (start / 1000, duration / 1000)
    }

    /// Parses the `(offsetMs,durationMs,0)word` groups of a yrc line.
    private static func parseYRCWords(_ line: String) -> [LyricWord] {
        var words: [LyricWord] = []
        var scanIndex = line.startIndex

        while let open = line[scanIndex...].firstIndex(of: "("),
              let close = line[open...].firstIndex(of: ")") {
            let body = line[line.index(after: open)..<close]
            let parts = body.split(separator: ",")
            guard parts.count >= 2,
                  let offset = Double(parts[0]),
                  let duration = Double(parts[1])
            else {
                scanIndex = line.index(after: close)
                continue
            }

            // The word runs from just after the closing paren to the next
            // opening paren (or the end of the line).
            let wordStart = line.index(after: close)
            let nextOpen = line[wordStart...].firstIndex(of: "(")
            let wordEnd = nextOpen ?? line.endIndex
            let text = String(line[wordStart..<wordEnd])

            words.append(LyricWord(
                text: text,
                startTime: offset / 1000,
                duration: duration / 1000
            ))

            scanIndex = nextOpen ?? line.endIndex
            if scanIndex >= line.endIndex { break }
        }

        return words
    }

    // MARK: - Shared

    /// Sorts the lines and fills in each line's end time from the next line.
    private static func finalize(_ lines: [LyricLine]) -> [LyricLine] {
        let sorted = lines.sorted { $0.startTime < $1.startTime }
        var result: [LyricLine] = []
        result.reserveCapacity(sorted.count)

        for (index, line) in sorted.enumerated() {
            var updated = line
            if updated.endTime <= updated.startTime {
                // A line-level source has no duration of its own: it lasts until
                // the next line begins.
                updated.endTime = index + 1 < sorted.count
                    ? sorted[index + 1].startTime
                    : updated.startTime + 3
            }
            result.append(updated)
        }
        return result
    }

    // MARK: - richsync (Musixmatch)

    /// Parses the Musixmatch `richsync_body` format.
    ///
    /// The body is a JSON array of lines, each with:
    ///
    /// - `ts`: when the line starts, in seconds.
    /// - `te`: when the line ends, in seconds.
    /// - `l`: the characters of the line, each with an offset `o` in seconds
    ///   **relative to the start of the line**.
    /// - `x`: the text of the line, with `\n` where the line breaks.
    ///
    /// The character offsets are the finest timing available anywhere: they say
    /// exactly when each character is sung. The words are built by grouping the
    /// characters, and each word takes the offset of its first character and
    /// the end of its last one.
    ///
    /// - Returns: the parsed lines, or `nil` when the body could not be read.
    static func parseRichSync(_ raw: String) -> [LyricLine]? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let entries = json as? [[String: Any]]
        else { return nil }

        var lines: [LyricLine] = []

        for entry in entries {
            guard let start = entry["ts"] as? Double else { continue }
            let end = entry["te"] as? Double ?? start
            let characters = entry["l"] as? [[String: Any]] ?? []

            let words = words(from: characters, lineStart: start, lineEnd: end)
            let text = (entry["x"] as? String)
                ?? words.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty, !words.isEmpty else { continue }

            lines.append(LyricLine(
                startTime: start,
                endTime: end,
                text: text,
                words: words
            ))
        }

        return finalize(lines)
    }

    /// Builds the words of a line from its character offsets.
    ///
    /// A word runs from its first character to just before the next word
    /// starts. The character list does not always contain the spaces (a space
    /// can be implied by the jump between two characters' offsets), so the end
    /// of a word is taken from the start of the next word rather than from a
    /// space character. The last word runs to the end of the line.
    private static func words(
        from characters: [[String: Any]],
        lineStart: Double,
        lineEnd: Double
    ) -> [LyricWord] {
        // First pass: group the characters into words, remembering where each
        // one starts.
        struct Partial {
            var text: String
            var start: Double
        }

        var partials: [Partial] = []
        var current = ""
        var currentStart: Double?

        for character in characters {
            guard let value = character["c"] as? String else { continue }
            let offset = character["o"] as? Double ?? 0
            let absolute = lineStart + offset

            if value == " " {
                if !current.isEmpty, let start = currentStart {
                    partials.append(Partial(text: current, start: start))
                }
                current = ""
                currentStart = nil
                continue
            }

            if currentStart == nil { currentStart = absolute }
            current += value
        }

        if !current.isEmpty, let start = currentStart {
            partials.append(Partial(text: current, start: start))
        }

        // Second pass: each word lasts until the next one starts.
        return partials.enumerated().map { index, partial in
            let end = index + 1 < partials.count ? partials[index + 1].start : lineEnd
            return LyricWord(
                text: partial.text,
                startTime: partial.start,
                duration: max(end - partial.start, 0.01)
            )
        }
    }

    // MARK: - Plain lyrics

    /// Parses plain (unsynced) lyrics into lines without timing.
    ///
    /// The lines are given a placeholder timing so the rest of the app can
    /// treat them like any other; `WordInterpolator` replaces it with real
    /// timings derived from the song's own pace.
    static func parsePlainLyrics(_ raw: String) -> [LyricLine] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                LyricLine(
                    startTime: Double(index),
                    endTime: Double(index + 1),
                    text: text,
                    words: []
                )
            }
    }

    // MARK: - Credit filtering

    private static let creditMarkers = [
        "作词", "作曲", "编曲", "制作", "混音", "录音", "监制", "出品", "发行",
        "词", "曲", "编", "录", "混", "母带", "和声", "吉他", "贝斯", "鼓",
        "produced by", "written by", "composed by", "arranged by", "mixed by",
        "recorded by", "mastered by", "vocals", "lyrics by", "music by",
    ]

    /// Removes production-credit lines.
    ///
    /// These show up in the yrc files as JSON lines (already dropped by the
    /// parser) and in some LRC files as ordinary timed lines. They are not
    /// lyrics, and showing them while the song plays looks broken.
    static func filteringCredits(_ lines: [LyricLine]) -> [LyricLine] {
        lines.filter { line in
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return false }
            let lower = text.lowercased()
            return !creditMarkers.contains { lower.contains($0) }
        }
    }
}
