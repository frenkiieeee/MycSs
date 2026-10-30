import AppKit
import Foundation

/// Watches the mouse position to know when the user is moving it.
///
/// **Why not an event monitor**: `NSEvent.addGlobalMonitorForEvents` needs the
/// Input Monitoring permission, which is invasive. `NSEvent.mouseLocation` is a
/// plain class property that reports the current position without any
/// permission at all, and polling it a few times a second is enough to know
/// whether the pointer moved.
///
/// The purpose is subtle: the overlay covers the lock screen, so the user
/// cannot see where to type their password. When the pointer moves, the app
/// reveals that area and shows a hint, then fades it back out.
@MainActor
final class MouseWatcher {

    /// Called when the pointer moves, with the new position.
    var onMove: ((CGPoint) -> Void)?

    /// Called when a button is pressed, with the position of the pointer.
    ///
    /// The overlay never receives the clicks itself: it is click-through, so
    /// that the password field of the lock screen underneath can be used. The
    /// clicks are noticed here instead, which is what the eye button of the
    /// password hint needs.
    var onClick: ((CGPoint) -> Void)?

    /// How far the pointer has to travel to count as a movement.
    private let threshold: CGFloat = 12

    private var lastPosition: CGPoint = .zero
    /// Whether a button was down the last time.
    private var buttonWasDown = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        lastPosition = NSEvent.mouseLocation

        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let position = NSEvent.mouseLocation
        let dx = position.x - lastPosition.x
        let dy = position.y - lastPosition.y
        let moved = dx * dx + dy * dy > threshold * threshold
        if moved {
            lastPosition = position
            onMove?(position)
        }

        // A click is a button that was up and is now down.
        let buttonIsDown = NSEvent.pressedMouseButtons != 0
        if buttonIsDown, !buttonWasDown {
            onClick?(position)
        }
        buttonWasDown = buttonIsDown
    }
}
