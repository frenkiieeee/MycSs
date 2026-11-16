import CoreGraphics
import Foundation

/// Notices the Escape key, and nothing else.
///
/// It reads the **state of the keyboard** (is Escape down right now?), which the
/// system lets anyone read without a permission. It never looks at any other key,
/// so it cannot record what the user types. That is the reason the screensaver
/// uses it instead of `KeyboardWatcher`, which rebuilds the password.
@MainActor
final class EscapeWatcher {

    var onEscape: (() -> Void)?

    private var timer: Timer?
    private var wasDown = false

    func start() {
        guard timer == nil else { return }
        // Escape held while the screensaver opens must not close it at once.
        wasDown = Self.isEscapeDown()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let down = Self.isEscapeDown()
        if down, !wasDown { onEscape?() }
        wasDown = down
    }

    private static func isEscapeDown() -> Bool {
        CGEventSource.keyState(.combinedSessionState, key: 53)
    }
}
