import AppKit
import CoreGraphics
import Foundation

/// Tracks whether the screen is locked.
///
/// Two independent signals are combined:
///
/// 1. `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`, published on the
///    distributed notification centre by `loginwindow`. These fire on the
///    transitions and are the primary signal.
/// 2. `CGSessionCopyCurrentDictionary()`, which reports whether the session is on
///    the console. This is only consulted to *seed* the initial state, because a
///    process that starts while the screen is already locked would otherwise
///    believe it is unlocked forever — the transition notifications have already
///    been and gone by then.
final class LockState {

    /// Fires whenever the locked state changes.
    var onChange: ((Bool) -> Void)?

    private(set) var isLocked: Bool = false

    private var lastStateChange: Date = .distantPast
    private var cachedLocked: Bool = false

    init() {
        // The transition notifications are only posted by the system, so the
        // observation happens on a private queue and hops to the main actor for
        // the callback.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setLocked(true, source: "notification")
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setLocked(false, source: "notification")
        }
    }

    /// Seeds the state from the window server and starts observing transitions.
    func start() {
        guard !isDemo else {
            Log.line("lock: demo mode, the lock state is ignored")
            return
        }
        setLocked(Self.queryLockedState(), source: "seed")
        Log.line("lock: initial state isLocked=\(isLocked)")
    }

    /// Whether the demo mode is running.
    ///
    /// The demo shows the overlay as an ordinary window, so it must not follow
    /// the lock screen into its Space: the picture would come out empty and
    /// the window would be dragged off the screen.
    private let isDemo = CommandLine.arguments.contains("--demo")

    /// Reads the current state, cached for a short window.
    ///
    /// The window server round trip is not free, so the answer is cached and only
    /// re-read when the cache is older than a second. Notifications refresh the
    /// cache immediately, so in practice this is only hit on the very first read.
    func lockedNow() -> Bool {
        guard !isDemo else { return false }
        if Date().timeIntervalSince(lastStateChange) < 1.0 {
            return cachedLocked
        }
        let fresh = Self.queryLockedState()
        lastStateChange = Date()
        cachedLocked = fresh
        return fresh
    }

    private func setLocked(_ value: Bool, source: String) {
        guard value != isLocked else { return }
        isLocked = value
        lastStateChange = Date()
        cachedLocked = value
        Log.line("lock: \(value ? "LOCKED" : "UNLOCKED") (source: \(source))")
        onChange?(value)
    }

    /// `kCGSSessionOnConsoleKey` is 1 while the session owns the console and 0
    /// when the screen is locked.
    private static func queryLockedState() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        // Two keys say different things about the lock state, and they do not
        // always agree:
        //
        // - `kCGSSessionOnConsoleKey` is 1 while the session owns the console.
        // - `CGSSessionScreenIsLocked` says directly whether the screen is
        //   locked.
        //
        // The second is the explicit one, so it is preferred; the first is the
        // fallback. Both are logged when they disagree, because a disagreement is
        // what makes the overlay appear late or not at all.
        let onConsole = (session["kCGSSessionOnConsoleKey"] as? Bool) ?? true
        let screenLocked = session["CGSSessionScreenIsLocked"] as? Bool

        if let screenLocked, screenLocked != !onConsole {
            Log.line("""
            lock: the two lock signals disagree (onConsole: \(onConsole), \
            screenIsLocked: \(screenLocked))
            """)
        }

        if let screenLocked { return screenLocked }
        return !onConsole
    }
}
