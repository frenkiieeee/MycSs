import AppKit
import CoreGraphics
import Foundation

/// Watches what the user types at the lock screen.
///
/// **Why not an event monitor**: `NSEvent.addGlobalMonitorForEvents` for the
/// keyboard needs the Accessibility permission, which is invasive. A passive
/// event tap (`CGEvent.tapCreate` with `.listenOnly`) is created without any
/// permission, but on a recent macOS the system does not deliver the keyboard
/// events to it unless the app is allowed to, so the tap sees nothing.
///
/// What does work without permissions is the **state of the keyboard**: the
/// system knows which keys are pressed at this moment, and the app can read it.
/// So the keys are polled, and the ones that were not down a moment ago are
/// the ones that were just pressed.
///
/// **What the app does with them**: the lock screen's field belongs to
/// `loginwindow` and its content cannot be read — not with the Accessibility
/// permission either, because a secure field stays unreadable on purpose. The
/// app therefore rebuilds what the user writes from the keys it sees, and it
/// shows it masked. The eye button is the user's own choice to look at it.
@MainActor
final class KeyboardWatcher {

    /// Called when the user presses a key.
    var onKey: (() -> Void)?

    /// Called with the whole text when it changes.
    var onText: ((String) -> Void)?

    /// The keys that are polled, and the character they write.
    ///
    /// The codes are the ones of the United States layout, which is what the
    /// overwhelming majority of keyboards use. The characters are only used for
    /// the eye button: the dots, which are what the user normally sees, do not
    /// depend on the layout at all.
    private static let layout: [Int: (unshifted: Character, shifted: Character)] = [
        0: ("a", "A"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"), 4: ("h", "H"),
        5: ("g", "G"), 6: ("z", "Z"), 7: ("x", "X"), 8: ("c", "C"), 9: ("v", "V"),
        11: ("b", "B"), 12: ("q", "Q"), 13: ("w", "W"), 14: ("e", "E"), 15: ("r", "R"),
        16: ("y", "Y"), 17: ("t", "T"), 18: ("1", "!"), 19: ("2", "@"), 20: ("3", "#"),
        21: ("4", "$"), 22: ("6", "^"), 23: ("5", "%"), 24: ("=", "+"), 25: ("9", "("),
        26: ("7", "&"), 27: ("-", "_"), 28: ("8", "*"), 29: ("0", ")"), 30: ("]", "}"),
        31: ("o", "O"), 32: ("u", "U"), 33: ("[", "{"), 34: ("i", "I"), 35: ("p", "P"),
        37: ("l", "L"), 38: ("j", "J"), 39: ("'", "\""), 40: ("k", "K"), 41: (";", ":"),
        43: (",", "<"), 44: ("/", "?"), 45: ("n", "N"), 46: ("m", "M"), 47: (".", ">"),
        50: ("`", "~"), 53: ("\\", "|"),
    ]

    /// The backspace and the forward delete.
    private static let backspace: Set<Int> = [51, 117]
    /// The return.
    private static let returnKey = 36
    /// The left and the right shift.
    private static let shifts: Set<Int> = [56, 60]

    /// The keys that are polled.
    private static let watched: [Int] = Array(layout.keys).sorted() + [51, 117, 36, 56, 60]

    private var timer: Timer?
    /// The keys that were down the last time.
    private var down: Set<Int> = []
    /// What the user has written.
    private var typed = ""

    /// How many keys have been seen.
    ///
    /// It comes from the system's counter, which counts the key presses even
    /// when the lock screen has the secure input on (it is the only thing
    /// that is still visible then).
    private(set) var pressedCount = 0

    /// The counter of the system, as it was the last time it was read.
    private var lastCounter: Double = 0

    /// Whether the app can tell which keys were pressed.
    ///
    /// The lock screen hides the state of the keyboard while the password is
    /// being typed, so on it only the number of presses is known.
    var knowsTheCharacters: Bool { !typed.isEmpty }

    func start() {
        guard timer == nil else { return }

        // The keys that are already down are not a key press: they were held
        // before the app started watching.
        for code in Self.watched
        where CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) {
            down.insert(code)
        }
        lastCounter = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )

        // Sixteen times a second: fast enough that the dots appear with the
        // key press, and slow enough not to cost anything.
        let timer = Timer(timeInterval: 0.016, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Forgets what was written.
    func reset() {
        down = []
        typed = ""
        pressedCount = 0
        onText?("")
    }

    /// What the user has written.
    var text: String { typed }

    private func check() {
        // The counter of the system: it goes back to zero with every key
        // press. It works even with the secure input of the lock screen, which
        // is the only thing the app can see there.
        let since = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )
        if since < lastCounter {
            pressedCount += 1
            onKey?()
        }
        lastCounter = since

        // The state of the keys: it says which keys were pressed, but the lock
        // screen hides it while the password is being typed.
        var current: Set<Int> = []
        for code in Self.watched
        where CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) {
            current.insert(code)
        }

        let fresh = current.subtracting(down)
        down = current
        guard !fresh.isEmpty else { return }

        // The shift changes the character of the key that is pressed.
        let shifted = !Self.shifts.isDisjoint(with: current)

        for code in fresh.sorted() {
            if Self.backspace.contains(code) {
                if !typed.isEmpty { typed.removeLast() }
            } else if code == Self.returnKey {
                continue
            } else if let key = Self.layout[code] {
                typed.append(shifted ? key.shifted : key.unshifted)
            }
        }

        onText?(typed)
    }
}
