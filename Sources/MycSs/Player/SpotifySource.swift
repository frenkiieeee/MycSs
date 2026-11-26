import Foundation

/// Reads the current track and playback position from the Spotify desktop app.
///
/// **Why AppleScript and not the Spotify Web API**: the Web API's playback
/// endpoints require an OAuth login for a Premium account and a registered
/// application. AppleScript talks to the app the user already has installed and
/// logged into, needs no credentials, and works on free accounts. The only cost
/// is a one-time macOS "Automation" permission prompt.
///
/// **Why the reading is split in two**: every Apple Event costs a round trip to
/// Spotify, and each property asked for adds about 8 ms. Measured on this
/// machine:
///
/// | Script | Cost |
/// |---|---|
/// | position + state | ~17 ms |
/// | position + state + title | ~25 ms |
/// | position + the whole track | ~50 ms |
///
/// So the fast reading asks for the position, the state and the **title**, and
/// the title is what identifies the track. The rest of the metadata (artist,
/// album, length) is only fetched when the title changes, which happens once
/// per song instead of several times per second.
///
/// **Why the reading happens off the main thread**: even at 25 ms, doing it on
/// the main thread would cost frames. The reading runs on a private queue and
/// the result is handed back asynchronously.
///
/// Three pitfalls are handled here, all of them found by running the script on
/// this machine:
///
/// 1. `st` is a reserved token in AppleScript (`set st to …` fails with -2741),
///    so the player state is bound to `pState`.
/// 2. The system locale is `en_ES`, so numbers come back with a **comma** as the
///    decimal separator (`AppleScriptValue.number` handles it).
/// 3. `spotify url of t` cannot be assigned to a variable (-10003, "access not
///    allowed"), so it has to be read inline in the returned list.
struct SpotifySource: PlayerSource {

    let id: NowPlaying.Source = .spotify


    /// The fast script: position, playing state and the track title.
    ///
    /// The title is the cheapest reliable way to know that the track changed.
    private static let positionScript = """
    if application "Spotify" is running then
        tell application "Spotify"
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

    /// The slow script: the rest of the track's metadata.
    ///
    /// Only run when the title changes, so its ~30 ms cost does not matter.
    private static let trackScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            try
                set t to current track
                set ar to artist of t
                set al to album of t
                set dur to (duration of t) / 1000
                return {name of t, ar, al, dur, spotify url of t}
            on error
                return {"", "", "", 0, ""}
            end try
        end tell
    else
        return {"", "", "", 0, ""}
    end if
    """

    /// The queue the Apple Event runs on.
    ///
    /// It is a serial queue of its own so that two readings never overlap and
    /// the caller is never blocked.
    private static let queue = DispatchQueue(label: "com.mycss.spotify", qos: .userInitiated)

    /// The compiled scripts.
    ///
    /// Compiling an AppleScript is not free, so they are compiled once.
    private static let compiledPositionScript = NSAppleScript(source: positionScript)
    private static let compiledTrackScript = NSAppleScript(source: trackScript)
    private static let compiledArtworkScript = NSAppleScript(source: artworkScript)

    // MARK: - Position

    /// Reads the position, off the main thread.
    ///
    /// - Parameter completion: called with the result, on the reading queue.
    func readPosition(completion: @escaping (PlayerSnapshot) -> Void) {
        Self.queue.async {
            let started = Date()
            let (isPlaying, position, title) = Self.runPosition()
            let latency = Date().timeIntervalSince(started)

            // The position is sampled somewhere along the round trip, so it is
            // already a little stale by the time it arrives. Pushing it forward
            // by half the round trip corrects for that: the sample is on
            // average halfway through.
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

    // MARK: - Track metadata

    /// Reads the rest of the track's metadata, off the main thread.
    ///
    /// - Parameter completion: called with the result, on the reading queue.
    func readTrack(completion: @escaping (PlayerTrackMetadata) -> Void) {
        Self.queue.async {
            let (title, artist, album, duration, url) = Self.runTrack()
            completion(PlayerTrackMetadata(
                title: title,
                artist: artist,
                album: album,
                durationSec: duration,
                trackURL: url.isEmpty ? nil : url
            ))
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

        let state = AppleScriptValue.string(output.atIndex(1))
        let position = AppleScriptValue.number(output.atIndex(2))
        let title = AppleScriptValue.string(output.atIndex(3))
        return (state.lowercased() == "playing", position, title)
    }

    private static func runTrack() -> (String, String, String, Double, String) {
        guard let script = compiledTrackScript else { return ("", "", "", 0, "") }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)

        if let error {
            report(error)
            return ("", "", "", 0, "")
        }
        guard output.numberOfItems >= 5 else { return ("", "", "", 0, "") }

        return (
            AppleScriptValue.string(output.atIndex(1)),
            AppleScriptValue.string(output.atIndex(2)),
            AppleScriptValue.string(output.atIndex(3)),
            AppleScriptValue.number(output.atIndex(4)),
            AppleScriptValue.string(output.atIndex(5))
        )
    }

    // MARK: - Commands and artwork

    func send(_ command: PlayerCommand) {
        AppleScriptValue.run(command, app: "Spotify", on: Self.queue)
    }

    /// The artwork URL for the current track. Read separately because it is only
    /// needed once per track; it can lag behind the track for a moment (see
    /// `CoverProvider`).
    func artworkURL() -> String? {
        // On the player's own queue, so it never overlaps another Apple Event.
        // Callers are never on that queue (they are the main thread or a
        // detached task), so `sync` cannot deadlock.
        Self.queue.sync {
            guard let script = Self.compiledArtworkScript else { return nil }
            var error: NSDictionary?
            let output = script.executeAndReturnError(&error)
            guard error == nil else { return nil }
            guard let value = output.stringValue, !value.isEmpty else { return nil }
            return value
        }
    }

    private static let artworkScript = """
    if application "Spotify" is running then
        tell application "Spotify"
            try
                return artwork url of current track
            on error
                return ""
            end try
        end tell
    else
        return ""
    end if
    """

    // MARK: - Errors

    private static var didReportPermissionDenied = false

    private static func report(_ error: NSDictionary) {
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        // -600 = the app is not running (expected), -1743 = Automation
        // permission was denied. Only the latter is worth telling the user
        // about, and only once.
        if code == -1743 {
            guard !didReportPermissionDenied else { return }
            didReportPermissionDenied = true
            Log.error("""
            spotify: Automation permission denied. Enable it in
            System Settings > Privacy & Security > Automation > MycSs > Spotify
            """)
        } else if code != -600 {
            Log.warn("spotify: AppleScript error \(code)")
        }
    }
}
