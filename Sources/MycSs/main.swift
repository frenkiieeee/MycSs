import AppKit
import Foundation

/// Entry point.
///
/// The setup is explicit rather than using `@main` on the `NSApplicationDelegate`:
/// `NSApplication.main()` never assigns the delegate, so
/// `applicationDidFinishLaunching` would never fire. The delegate is also held in
/// a strong static reference because `NSApplication.delegate` is weak.
let application = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.retainedDelegate = delegate
application.delegate = delegate
// An agent app: no Dock icon, just the menu bar item.
application.setActivationPolicy(.accessory)

if CommandLine.arguments.contains("--inspect-spaces") {
    SpaceInspector.run()
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    // The self test talks to the network and to Spotify, so it runs the main
    // run loop until it finishes.
    Task {
        await SelfTest.run()
        exit(0)
    }
    application.run()
    exit(0)
}

application.run()
