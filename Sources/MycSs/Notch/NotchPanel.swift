import AppKit
import SwiftUI

/// The window of the notch: borderless, above the menu bar, and never the key
/// window, so it cannot steal the focus from what the user is doing.
///
/// It has one fixed size, as big as the notch open, and it is transparent; the
/// black shape that grows and shrinks is drawn inside it, so the window is never
/// resized (which would stutter).
///
/// **`ignoresMouseEvents` is never touched, on purpose.** A transparent
/// borderless window lets the clicks through wherever it draws nothing, and takes
/// them where it draws. That is exactly what the notch needs: the menu bar under
/// the empty part of the window keeps working, and the notch gets real hover and
/// real clicks, so its controls are ordinary SwiftUI buttons. Setting the
/// property, to either value, turns that automatic behaviour off.
final class NotchPanel: NSPanel {

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Above the menu bar and the status items.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

/// The hosting view of the notch. The window is never key, so the first click on
/// it has to count as a click and not as "activate the window".
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
