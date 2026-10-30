import AppKit
import SwiftUI

/// A borderless, click-through panel that sits above the lock screen.
///
/// Two properties matter for the lock screen specifically:
///
/// - `ignoresMouseEvents` is on, so the panel never swallows the clicks that the
///   user needs to type their password into the login window underneath.
/// - `canBecomeKey` is false and it is a non-activating panel, so the overlay
///   never steals keyboard focus from the login window. If it did, the password
///   field would stop receiving keystrokes and the screen could not be unlocked.
///
/// **The Space behaviour is configurable.** A panel that joins every Space
/// (`.canJoinAllSpaces` + `.fullScreenAuxiliary`) is what makes the overlay
/// survive the lock screen, but it also makes the app appear on every Space and
/// shifts the Dock. The preview therefore uses a different behaviour, because
/// there it only has to sit on the current Space.
final class LockOverlayPanel: NSPanel {

    /// Whether the panel should appear on every Space.
    ///
    /// True for the real lock screen overlay, false for the preview.
    var joinsAllSpaces = true {
        didSet { applyCollectionBehaviour() }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        applyCollectionBehaviour()
    }

    private func applyCollectionBehaviour() {
        if joinsAllSpaces {
            collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
                .ignoresCycle,
            ]
        } else {
            // The preview stays on the current Space, so it does not disturb the
            // Dock or appear on the lock screen.
            collectionBehavior = [
                .stationary,
                .ignoresCycle,
            ]
        }
    }
}
