import Foundation

/// Reads the current track and playback position from the Music app.
///
/// It works exactly like `SpotifySource`, and for the same reasons (see there for
/// the measurements): AppleScript instead of MediaRemote (see
/// `docs/decisions/001-applescript-no-mediaremote.md`), a cheap reading several
/// times per second and an expensive one once per track, all of it on a private
/// serial queue.
///
/// Differences from Spotify that matter:
///
/// - Music reports the duration in **seconds**; Spotify reports milliseconds.
/// - Music has no web URL for the artwork. It hands over the image itself, as
///   raw data, so `artworkURL()` is nil and `artworkData()` carries the cover.
/// - There is no `spotify url` equivalent, so `trackURL` is nil.
///
/// The same pitfalls apply as with Spotify: the decimal separator follows the
/// system locale (`157,53`), and the variable that holds the player state must
/// not be called `st`.
struct AppleMusicSource: PlayerSource {

    let id: NowPlaying.Source = .appleMusic

    private static let positionScript = """
    if application "Music" is running then
        tell application "Music"
            try
                set pState to (player state as text)
                set p to player position
                set nm to name of current track
                return {pState, p, nm}
            on error
                return {"stopped", 0, ""}
            end try
        end tell
    else
        return {"stopped", 0, ""}
    end if
    """

    private static let trackScript = """
    if application "Music" is running then
        tell application "Music"
            try
                set t to current track
                set ar to artist of t
                set al to album of t
                set dur to duration of t
                return {ar, al, dur}
            on error
                return {"", "", 0}
            end try
        end tell
    else
        return {"", "", 0}
    end if
    """

    /// The cover as raw bytes. The image format is whatever Music stores
    /// (JPEG, PNG or TIFF), and `NSImage` reads all of them.
    private static let artworkScript = """
    if application "Music" is running then
        tell application "Music"
            try
                set t to current track
                if (count of artworks of t) > 0 then
                    return data of artwork 1 of t
                end if
                return ""
            on error
                return ""
            end try
        end tell
    else
        return ""
    end if
    """

    private static let queue = DispatchQueue(label: "com.mycss.music", qos: .userInitiated)

    private static let compiledPositionScript = NSAppleScript(source: positionScript)
    private static let compiledTrackScript = NSAppleScript(source: trackScript)
    private static let compiledArtworkScript = NSAppleScript(source: artworkScript)

    // MARK: - PlayerSource

    func readPosition(completion: @escaping (PlayerSnapshot) -> Void) {
        Self.queue.async {
            let started = Date()
            let (isPlaying, position, title) = Self.runPosition()
            let latency = Date().timeIntervalSince(started)

            // Same correction as Spotify: the sample is taken halfway through
            // the round trip.
            var adjusted = position
            if isPlaying, latency > 0, latency < 1 {
                adjusted += latency * 0.5
            }

            completion(PlayerSnapshot(
                isPlaying: isPlaying,
                positionSec: adjusted,
                title: title,
                latency: latency,
                takenAt: Date()
            ))
        }
    }

    func readTrack(completion: @escaping (PlayerTrackMetadata) -> Void) {
        Self.queue.async {
            let (artist, album, duration) = Self.runTrack()
            completion(PlayerTrackMetadata(
                artist: artist,
                album: album,
                durationSec: duration,
                trackURL: nil
            ))
        }
    }

    func artworkURL() -> String? { nil }

    func send(_ command: PlayerCommand) {
        AppleScriptValue.run(command, app: "Music", on: Self.queue)
    }

    func artworkData() -> Data? {
        // On the player's own queue, so it never overlaps another Apple Event.
        Self.queue.sync {
            guard let script = Self.compiledArtworkScript else { return nil }
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            guard error == nil else { return nil }
            let data = output.data
            return data.isEmpty ? nil : data
        }
    }

    // MARK: - Script execution

    private static func runPosition() -> (Bool, TimeInterval, String) {
        guard let script = compiledPositionScript else { return (false, 0, "") }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            report(error)
            return (false, 0, "")
        }
        guard output.numberOfItems >= 3 else { return (false, 0, "") }

        return (
            AppleScriptValue.string(output.atIndex(1)).lowercased() == "playing",
            AppleScriptValue.number(output.atIndex(2)),
            AppleScriptValue.string(output.atIndex(3))
        )
    }

    private static func runTrack() -> (String, String, Double) {
        guard let script = compiledTrackScript else { return ("", "", 0) }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            report(error)
            return ("", "", 0)
        }
        guard output.numberOfItems >= 3 else { return ("", "", 0) }

        return (
            AppleScriptValue.string(output.atIndex(1)),
            AppleScriptValue.string(output.atIndex(2)),
            AppleScriptValue.number(output.atIndex(3))
        )
    }

    // MARK: - Errors

    private static var didReportPermissionDenied = false

    private static func report(_ error: NSDictionary) {
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        // -600 = not running (expected), -1743 = Automation permission denied.
        if code == -1743 {
            guard !didReportPermissionDenied else { return }
            didReportPermissionDenied = true
            Log.error("""
            music: Automation permission denied. Enable it in
            System Settings > Privacy & Security > Automation > MycSs > Music
            """)
        } else if code != -600 {
            Log.warn("music: AppleScript error \(code)")
        }
    }
}

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
