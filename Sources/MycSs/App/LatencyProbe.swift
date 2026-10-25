import Foundation

/// Measures how stale the Apple Event reading actually is.
///
/// The reader compensates the latency by adding half of the round-trip time to
/// the position. Whether that is the right correction depends on *when* inside
/// the round trip Spotify actually samples the position.
///
/// This test reads the position twice in a row and compares how much the
/// position advanced against how much wall-clock time passed. If the reading is
/// fresh (sampled at the end of the round trip), the position advances by the
/// full elapsed time. If it is sampled at the start, it advances by less.
enum LatencyProbe {

    static func run() {
        print("== Latency probe ==")

        for attempt in 0..<4 {
            // Read 1: timed.
            let start = Date()
            let first = positionNow()
            let middle = Date()

            // Read 2: as soon as possible afterwards.
            let second = positionNow()
            let end = Date()

            let roundTrip = middle.timeIntervalSince(start)
            let gap = end.timeIntervalSince(middle)
            let advanced = second - first

            // How much of the gap is explained by the position advancing.
            let explained = gap > 0 ? advanced / gap : 0

            print(String(format: "  #%d  roundTrip=%.0fms  gap=%.0fms  position advanced=%.0fms  (%.0f%% of the gap)",
                         attempt + 1,
                         roundTrip * 1000,
                         gap * 1000,
                         advanced * 1000,
                         explained * 100))
        }
    }

    /// Reads the position with the same script the app uses.
    private static func positionNow() -> Double {
        let script = """
        tell application "Spotify"
            set p to player position
            return p
        end tell
        """
        guard let source = NSAppleScript(source: script) else { return 0 }
        var error: NSDictionary?
        let output = source.executeAndReturnError(&error)
        guard error == nil, let raw = output.stringValue else { return 0 }
        return Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
