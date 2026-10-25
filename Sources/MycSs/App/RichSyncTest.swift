import Foundation

/// Checks the `richsync` parser against the example from Musixmatch's own
/// documentation.
///
/// The format is character-level timing, which is the finest the app can get, so
/// it is worth being sure the parser reads it correctly.
enum RichSyncTest {

    /// The first three lines of the example in Musixmatch's documentation for
    /// `track.richsync.get`.
    static let sample = """
    [{"ts":0.09,"te":2.05,"l":[{"c":"(","o":0},{"c":"'Til","o":0.011},{"c":" ","o":0.101},{"c":"I'm","o":0.431},{"c":" ","o":0.575},{"c":"in","o":0.862},{"c":" ","o":0.938},{"c":"the","o":1.161},{"c":" ","o":1.26},{"c":"grave)","o":1.526}],"x":"('Til I'm in the grave)"},{"ts":3.92,"te":5.409,"l":[{"c":"I","o":0},{"c":" ","o":0.022},{"c":"want","o":0.11},{"c":" ","o":0.2849},{"c":"you","o":0.509},{"c":" ","o":0.663},{"c":"to","o":0.8189},{"c":" ","o":0.908},{"c":"stay","o":1.0008}],"x":"I want you to stay"},{"ts":8.34,"te":9.89,"l":[{"c":"'Til","o":0},{"c":" ","o":0.133},{"c":"I'm","o":0.273},{"c":" ","o":0.465},{"c":"in","o":0.642},{"c":" ","o":0.702},{"c":"the","o":0.846},{"c":" ","o":1.006},{"c":"grave","o":1.159}],"x":"'Til I'm in the grave"}]
    """

    static func run() {
        print("-- LyricsParser.parseRichSync --")

        guard let lines = LyricsParser.parseRichSync(sample) else {
            print("  !! FAILED to parse")
            return
        }

        print("  lines: \(lines.count)")
        for line in lines {
            print(String(format: "  %.2fs → %.2fs  %@", line.startTime, line.endTime, line.text))
            for word in line.words {
                print(String(format: "      '%@'  %.3fs → %.3fs",
                             word.text, word.startTime, word.endTime))
            }
        }

        // The first line starts at 0.09 s and its words carry the character
        // offsets: "'Til" at 0.090, "I'm" at 0.521, "in" at 0.952, "the" at 1.251
        // and "grave)" at 1.616.
        guard let first = lines.first else { return }
        let offsets = first.words.map(\.startTime)
        let expected: [Double] = [0.09, 0.521, 0.952, 1.251, 1.616]

        if first.words.count == 5 {
            print("  OK: 5 words parsed")
        } else {
            print("  !! expected 5 words, got \(first.words.count)")
        }

        // A word has to last until the next one starts, not just for its
        // first character.
        let durations = first.words.map(\.duration)
        if durations.allSatisfy({ $0 > 0.05 }) {
            print("  OK: every word has a real duration")
        } else {
            print("  !! some words are too short: \(durations)")
        }

        let matches = zip(offsets, expected).allSatisfy { abs($0 - $1) < 0.001 }
        if matches {
            print("  OK: word timings match the character offsets")
        } else {
            print("  !! word timings wrong")
            print("     got:      \(offsets)")
            print("     expected: \(expected)")
        }

        // The word timings have to be monotonic: a word never starts before the
        // previous one.
        let monotonic = zip(first.words, first.words.dropFirst()).allSatisfy { $0.endTime <= $1.startTime + 0.001 }
        print(monotonic ? "  OK: timings are monotonic" : "  !! timings overlap")
    }
}
