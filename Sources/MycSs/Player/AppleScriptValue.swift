import Foundation

/// Reading values out of Apple Event descriptors.
enum AppleScriptValue {

    static func string(_ descriptor: NSAppleEventDescriptor?) -> String {
        descriptor?.stringValue ?? ""
    }

    /// Parses a number that may use a comma as the decimal separator.
    ///
    /// The system locale is `en_ES`, so AppleScript renders `157.53` as
    /// `"157,53"`. Without this the position would silently become 0 and the
    /// karaoke would freeze.
    static func number(_ descriptor: NSAppleEventDescriptor?) -> Double {
        guard let raw = descriptor?.stringValue else { return 0 }
        return Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

extension AppleScriptValue {

    /// The AppleScript statement for a command. Spotify and Music use the same
    /// words for these four.
    ///
    /// The position is written with a **point**: AppleScript source code always
    /// uses a point, even when the system locale prints results with a comma.
    static func statement(for command: PlayerCommand) -> String {
        switch command {
        case .playPause: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        case .seek(let seconds):
            return "set player position to " + String(format: "%.2f", max(0, seconds))
        }
    }

    /// Runs a command on the app's own queue, so it never overlaps a reading.
    static func run(_ command: PlayerCommand, app: String, on queue: DispatchQueue) {
        let source = """
        if application "\(app)" is running then
            tell application "\(app)" to \(statement(for: command))
        end if
        """
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error, (error[NSAppleScript.errorNumber] as? Int) != -600 {
                Log.warn("\(app): command \(command) failed: \(error)")
            }
        }
    }
}
