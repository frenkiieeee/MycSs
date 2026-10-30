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
///
/// **How the pauses are handled**: a line does not always fill the time until
/// the next line — the singer often pauses, and a long instrumental break
/// follows. The words are therefore distributed over the *natural* length of the
/// line (its characters at the song's pace) rather than over the whole slot, so
/// the highlight finishes when the singing finishes and waits quietly through
/// the pause instead of crawling across the words.
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
    static func interpolate(_ lines: [LyricLine], weighting: AppSettings.WordTiming = .weighted) -> [LyricLine] {
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

            // The words fill the natural length of the line. A pause after the
            // line is left empty on purpose: the highlight finishes with the
            // singing rather than dragging through the silence.
            let allotted: Double
            switch weighting {
            case .even:
                allotted = min(slot, natural * stretchFactor)
            case .weighted:
                allotted = min(slot, natural)
            }

            // Each word gets a share of the line, proportional to its length so
            // a long word is not rushed and a short one is not stretched.
            let weights = words.map { Double($0.count) }
            let totalWeight = max(weights.reduce(0, +), 1)

            var result: [LyricWord] = []
            result.reserveCapacity(words.count)
            var cursor = line.startTime
            for (index, word) in words.enumerated() {
                let share = allotted * (weights[index] / totalWeight)
                result.append(LyricWord(
                    text: word,
                    startTime: cursor,
                    duration: max(share, 0.05)
                ))
                cursor += share
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
