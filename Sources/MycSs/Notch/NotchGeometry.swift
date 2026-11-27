import SwiftUI
import UniformTypeIdentifiers

// MARK: - Geometry

/// The size of the physical notch and of the open one.
struct NotchGeometry {
    /// The cut-out of the screen, when it has one. `nil` on a screen without a notch.
    private var hardware: CGSize?
    /// The height of the menu bar of the screen (spec 017).
    var menuBar: CGFloat = 24

    /// A screen with a physical cut-out of this size.
    init(notch: CGSize) {
        hardware = notch
    }

    /// A screen without a notch (spec 017): the shape comes from the settings.
    static func plain(menuBar: CGFloat = 24) -> NotchGeometry {
        var geometry = NotchGeometry(notch: .zero)
        geometry.hardware = nil
        geometry.menuBar = menuBar
        return geometry
    }

    var hasHardwareNotch: Bool { hardware != nil }

    /// A floating island, under the menu bar.
    var isIsland: Bool { !hasHardwareNotch && AppSettings.shared.notchPlainStyle == .island }
    /// Nothing is drawn while there is nothing to show.
    var restsHidden: Bool { !hasHardwareNotch && AppSettings.shared.notchPlainRest == .hidden }

    /// The cut-out, or on a screen without one, the zone the notch rests in.
    var notch: CGSize {
        if let hardware { return hardware }
        return CGSize(width: CGFloat(AppSettings.shared.notchPlainWidth), height: isIsland ? 30 : menuBar)
    }

    /// The space in the middle of the closed notch that the sides leave free: the
    /// cut-out, or just a little breathing room where there is none.
    var contentGap: CGFloat { hasHardwareNotch ? notch.width : 22 }

    /// What the kinds that write a line of text under the cut-out (a notification, the
    /// title of a new song, the timer) take as width in the middle: where there is no
    /// cut-out the text still needs room.
    var textGap: CGFloat { hasHardwareNotch ? notch.width : 150 }

    /// The size of the idle notch. A floating island that rests hidden has no height:
    /// there is nothing under the menu bar to point at by mistake.
    var restSize: CGSize {
        isIsland && restsHidden ? CGSize(width: notch.width, height: 0) : notch
    }

    /// The height of the strip with the tabs and the gear when the notch is open. A
    /// screen without a cut-out keeps the same layout as one with it, whatever the
    /// height of its menu bar.
    var openHeader: CGFloat { hasHardwareNotch ? notch.height : 32 }

    /// How far under the top edge of the screen the shape hangs.
    var topInset: CGFloat { isIsland ? menuBar + 6 : 0 }

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
    /// The timer: it drops under the cut-out, like a notification, so the time never
    /// has to fit in the narrow side of the notch.
    static var timerRow: CGFloat { 30 * closedText }
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
            height: Self.baseOpen.height * Self.maxScale + Self.shadowPadding + 8 + topInset
        )
    }
}

/// What the notch is showing.
enum NotchKind: Equatable {
    case idle, wings, peek, hud, notification, timer, open
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
        // Where a notch has a cut-out, the sides keep clear of it; a screen without one
        // only leaves a little room.
        let gap = geometry.contentGap
        let textGap = geometry.textGap
        let settings = AppSettings.shared
        let music = hasTrack && notch.isListening
        let wings = settings.notchWings && music
        // On another screen it opens only where the pointer was; the others stay closed.
        let openHere = notch.isOpen && (display == 0 || notch.openDisplay == 0 || notch.openDisplay == display)

        if openHere {
            kind = .open
            body = NotchGeometry.openSize
            ear = NotchGeometry.openEar
            bottomRadius = 28 * min(NotchGeometry.scale, 1.15)
        } else if notch.hud != nil {
            kind = .hud
            body = CGSize(width: gap + NotchGeometry.hudWing * 2, height: cut.height)
            ear = 6
            bottomRadius = 12
        } else if notch.notification != nil {
            kind = .notification
            body = CGSize(
                width: textGap + (NotchGeometry.wing + NotchGeometry.notificationWing) * 2,
                height: cut.height + NotchGeometry.notificationRow
            )
            ear = 6
            bottomRadius = 20
        } else if notch.isPeeking, music {
            kind = .peek
            if settings.notchPeekStyle == .sides {
                body = CGSize(
                    width: gap + (NotchGeometry.wing + NotchGeometry.peekSide) * 2,
                    height: cut.height
                )
                bottomRadius = 14
            } else {
                body = CGSize(
                    width: textGap + NotchGeometry.wing * 2 + NotchGeometry.peekExtraWidth,
                    height: cut.height + NotchGeometry.peekRow
                )
                bottomRadius = 18
            }
            ear = 6
        } else if timerActive {
            kind = .timer
            body = CGSize(
                width: textGap + NotchGeometry.wing * 2 + NotchGeometry.peekExtraWidth * 0.5,
                height: cut.height + NotchGeometry.timerRow
            )
            ear = 6
            bottomRadius = 18
        } else if wings {
            kind = .wings
            // Never narrower than the zone it rests in.
            body = CGSize(width: max(gap + NotchGeometry.wing * 2, cut.width), height: cut.height)
            ear = 6
            bottomRadius = 12
        } else {
            // Idle: exactly the hardware notch, so nothing shows.
            kind = .idle
            body = geometry.restSize
            ear = 0
            bottomRadius = 10
        }
        // A floating island is round on every side and has no ears (spec 017).
        if geometry.isIsland {
            ear = 0
            bottomRadius = kind == .open ? bottomRadius : 24
        }
        // The user's roundness (spec 016); the idle notch keeps the hardware one.
        if kind != .idle { bottomRadius *= CGFloat(settings.notchCorner) }
    }
}
