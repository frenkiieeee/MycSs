import Foundation

/// Derives per-word timings from line-level lyrics.
///
/// When a provider only gives the start of each line, the words inside it have
/// to be distributed somehow. A fixed rate does not work: the measured pace of
/// singing varies by a factor of two between songs (and by up to six times
/// between lines within one song, on instrumental gaps).
///
/// The rate is therefore derived from the song's own lines: the median number of
/// milliseconds per character across the song. The median is used rather than the
/// mean because a few long instrumental gaps would drag a mean far away from
/// the typical pace. The median also gives a natural ceiling for each line, so a
/// line that ends early (because the singer paused) does not stretch its words
/// across the whole gap.
enum WordInterpolator {

    /// Bounds on the derived pace, in milliseconds per character.
    ///
    /// The lower bound stops words from racing ahead on fast lines; the upper
    /// bound stops them from lagging on slow ones.
    private static let minMsPerChar: Double = 70
    private static let maxMsPerChar: Double = 320

    /// How much longer than its share of the line a line is allowed to stretch,
    /// to absorb gaps between lines without letting words drift.
    private static let stretchFactor: Double = 1.35

    /// Fills in per-word timings for lines that only have a start time.
    static func interpolate(_ lines: [LyricLine]) -> [LyricLine] {
        guard !lines.isEmpty else { return [] }

        let pace = derivePace(from: lines)
        Log.line("interpolation: song pace \(Int(pace.rounded())) ms/char")

        return lines.map { line in
            // Lines that already have word timings are left untouched.
            guard !line.hasWordTiming else { return line }

            let words = splitIntoWords(line.text)
            guard !words.isEmpty else { return line }

            // The slot this line owns: from its start to the next line's start.
            let slot = max(line.endTime - line.startTime, 0.1)
            // How long the words should take at the song's pace.
            let natural = Double(line.text.count) * pace / 1000
            // The words may stretch past their natural length to fill the slot,
            // but never past the slot itself: that keeps an instrumental gap
            // from being filled with stretched words.
            let allotted = min(slot, natural * stretchFactor)
            // A floor, so a line of very short words still has a visible duration.
            let perWord = max(allotted / Double(words.count), 0.05)

            var result: [LyricWord] = []
            result.reserveCapacity(words.count)
            for (index, word) in words.enumerated() {
                result.append(LyricWord(
                    text: word,
                    startTime: line.startTime + Double(index) * perWord,
                    duration: perWord
                ))
            }

            var updated = line
            updated.words = result
            return updated
        }
    }

    /// Works out the song's pace in milliseconds per character.
    ///
    /// Measured across the lines that carry the actual singing, ignoring lines
    /// with no text (those are instrumental gaps, not singing).
    static func derivePace(from lines: [LyricLine]) -> Double {
        var samples: [Double] = []

        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.count > 0 else { continue }

            let next = index + 1 < lines.count ? lines[index + 1].startTime : line.endTime
            let duration = next - line.startTime
            guard duration > 0 else { continue }

            // Extremely long lines are instrumental gaps, not singing.
            guard duration < 12 else { continue }

            samples.append(duration / Double(text.count) * 1000)
        }

        guard !samples.isEmpty else { return (minMsPerChar + maxMsPerChar) / 2 }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        return min(max(median, minMsPerChar), maxMsPerChar)
    }

    /// Splits a line into words, keeping the trailing whitespace on each word so
    /// the text can be reassembled exactly.
    private static func splitIntoWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if character == " " {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        return words
    }
}
