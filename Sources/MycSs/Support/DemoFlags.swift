import Foundation

/// The command line flags that run the app on a demo song instead of the real
/// player. One place reads them, so a new flag is not searched for in the code.
///
/// - `--demo`: a demo song, demo events, reminders and clipboard (nothing real is touched).
/// - `--demo-nolyrics`: the demo song has no lyrics.
/// - `--demo-paused`: the demo song starts paused.
/// - `--demo-mascot`: the cover of the demo is the mascot.
/// - `--snapshot-loading`: the overlay shows the state while lyrics load.
enum DemoFlags {
    private static let arguments = CommandLine.arguments

    static let isDemo = arguments.contains("--demo")
    static let noLyrics = arguments.contains("--demo-nolyrics")
    static let paused = arguments.contains("--demo-paused")
    static let mascot = arguments.contains("--demo-mascot")
    static let loading = arguments.contains("--snapshot-loading")
}
