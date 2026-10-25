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
final class LockOverlayPanel: NSPanel {

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
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
    }
}
