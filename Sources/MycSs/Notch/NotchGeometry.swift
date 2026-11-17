import SwiftUI
import UniformTypeIdentifiers

// MARK: - Geometry

/// The size of the physical notch and of the open one.
struct NotchGeometry {
    /// The cut-out in the screen (or a virtual one on a Mac without a notch).
    var notch: CGSize

    /// The open notch is designed at this size and then scaled by the user's setting.
    static let baseOpen = CGSize(width: 640, height: 176)
    static let maxScale: CGFloat = 1.3
    static var scale: CGFloat { CGFloat(AppSettings.shared.notchScale) }
    static var openSize: CGSize { CGSize(width: baseOpen.width * scale, height: baseOpen.height * scale) }

    /// How big the closed notch is, from the user's setting. Its sides, the
    /// indicator, the title beside the cut-out and what is drawn on them follow it.
    static var closedScale: CGFloat { CGFloat(AppSettings.shared.notchClosedScale) }
    /// Text and icons shrink a little less than the shape, so they stay legible.
    static var closedText: CGFloat { max(closedScale, 0.82) }

    /// How much each side grows for the cover and the visualiser.
    static var wing: CGFloat { 58 * closedScale }
    /// How much each side grows for the volume and brightness indicator.
    static var hudWing: CGFloat { 96 * closedText }
    /// The title beside the cut-out, when the notch grows to the sides.
    /// What grows with the sides while the new song shows: the cover and the text.
    static var peekBoost: CGFloat { min(max(1, 1 + (CGFloat(AppSettings.shared.notchPeekWidth) - 1) * 0.45), 1.35) }
    static var peekSide: CGFloat {
        // Never wider than the window that holds the notch can show.
        min(104 * closedScale * CGFloat(AppSettings.shared.notchPeekWidth), 300 - wing)
    }
    /// The title under the cut-out, when the notch grows down.
    static var peekExtraWidth: CGFloat { 70 * closedScale }
    static var peekRow: CGFloat { 34 * closedText }
    /// A notification: a little wider than the wings, and a row of text.
    static var notificationWing: CGFloat { 50 * closedScale }
    static var notificationRow: CGFloat { 44 * closedText }
    /// The space at the outer edge of each side.
    static var sidePadding: CGFloat { 14 * closedScale }
    /// Room around the shape for its shadow.
    static let shadowPadding: CGFloat = 22
    static let openEar: CGFloat = 16

    /// The window that holds the notch, at the top centre of the screen. It is as
    /// big as the notch can be at its largest, so it never has to be resized.
    var panelSize: CGSize {
        CGSize(
            width: Self.baseOpen.width * Self.maxScale + (Self.openEar + Self.shadowPadding) * 2,
            height: Self.baseOpen.height * Self.maxScale + Self.shadowPadding + 8
        )
    }
}

/// What the notch is showing.
enum NotchKind: Equatable {
    case idle, wings, peek, hud, notification, open
}

/// What the notch looks like right now: its size and its corners.
struct NotchLayout: Equatable {
    var kind: NotchKind
    var body: CGSize
    /// The radius of the top corners, which curve outwards into the menu bar.
    var ear: CGFloat
    var bottomRadius: CGFloat

    var isOpen: Bool { kind == .open }

    @MainActor
    init(notch: NotchModel, geometry: NotchGeometry, hasTrack: Bool, timerActive: Bool = false,
         display: CGDirectDisplayID = 0) {
        let cut = geometry.notch
        let settings = AppSettings.shared
        let music = hasTrack && notch.isListening
        let wings = (settings.notchWings && music) || timerActive
        // On another screen it opens only where the pointer was; the others stay closed.
        let openHere = notch.isOpen && (display == 0 || notch.openDisplay == 0 || notch.openDisplay == display)

        if openHere {
            kind = .open
            body = NotchGeometry.openSize
            ear = NotchGeometry.openEar
            bottomRadius = 28 * min(NotchGeometry.scale, 1.15)
        } else if notch.hud != nil {
            kind = .hud
            body = CGSize(width: cut.width + NotchGeometry.hudWing * 2, height: cut.height)
            ear = 6
            bottomRadius = 12
        } else if notch.notification != nil {
            kind = .notification
            body = CGSize(
                width: cut.width + (NotchGeometry.wing + NotchGeometry.notificationWing) * 2,
                height: cut.height + NotchGeometry.notificationRow
            )
            ear = 6
            bottomRadius = 20
        } else if notch.isPeeking, music {
            kind = .peek
            if settings.notchPeekStyle == .sides {
                body = CGSize(
                    width: cut.width + (NotchGeometry.wing + NotchGeometry.peekSide) * 2,
                    height: cut.height
                )
                bottomRadius = 14
            } else {
                body = CGSize(
                    width: cut.width + NotchGeometry.wing * 2 + NotchGeometry.peekExtraWidth,
                    height: cut.height + NotchGeometry.peekRow
                )
                bottomRadius = 18
            }
            ear = 6
        } else if wings {
            kind = .wings
            body = CGSize(width: cut.width + NotchGeometry.wing * 2, height: cut.height)
            ear = 6
            bottomRadius = 12
        } else {
            // Idle: exactly the hardware notch, so nothing shows.
            kind = .idle
            body = cut
            ear = 0
            bottomRadius = 10
        }
    }
}
