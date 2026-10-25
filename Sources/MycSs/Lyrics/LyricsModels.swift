import Foundation

/// A single word inside a lyric line, with its own timing.
struct LyricWord: Equatable {
    /// The word as it should be displayed, including trailing whitespace so the
    /// text can be reassembled exactly.
    var text: String
    /// When the word starts being sung, in seconds from the start of the track.
    var startTime: TimeInterval
    /// How long the word lasts, in seconds. May be estimated.
    var duration: TimeInterval

    var endTime: TimeInterval { startTime + duration }

    /// The word without trailing whitespace, for comparisons.
    var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var isBlank: Bool { trimmed.isEmpty }
}

/// A line of lyrics with its timing and the words inside it.
struct LyricLine: Equatable {
    /// When the line starts, in seconds from the start of the track.
    var startTime: TimeInterval
    /// When the line ends. For line-level sources this is the start of the next
    /// line, which is only known once all lines have been parsed.
    var endTime: TimeInterval
    var text: String
    var words: [LyricWord]

    /// True when the line has no words with their own timing, only a line start.
    var hasWordTiming: Bool {
        words.contains { !$0.isBlank }
    }
}

/// A complete set of lyrics for one track.
struct Lyrics: Equatable {
    var lines: [LyricLine]
    /// The track duration the lyrics were matched against.
    var duration: TimeInterval
    /// Which provider the lyrics came from.
    var source: Source
    /// Whether the word timings are real or synthesised.
    var wordTimingQuality: WordTimingQuality

    enum Source: String {
        case lrclib
        case netease
        case musixmatch
    }

    enum WordTimingQuality: String {
        /// Every word has its own timing from the provider.
        case real
        /// Word timings were derived from line timings.
        case interpolated
    }

    var isEmpty: Bool { lines.isEmpty }

    /// The index of the line that is active at `position`, or `nil` before the
    /// first line starts.
    func activeLineIndex(at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        // Binary search for the last line that starts at or before the position.
        var low = 0
        var high = lines.count - 1
        var result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startTime <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
