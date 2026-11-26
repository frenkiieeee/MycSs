import SwiftUI
import UniformTypeIdentifiers

// MARK: - Style

/// The colours of the notch, from the user's choice.
enum NotchPalette {
    @MainActor
    static func accent(_ model: LyricsViewModel) -> Color {
        switch AppSettings.shared.notchAccent {
        case .album: return model.theme.accent.color
        case .yellow: return brandYellow
        case .white: return .white
        case .amber: return Color(red: 1.0, green: 0.70, blue: 0.30)
        case .sky: return Color(red: 0.42, green: 0.74, blue: 1.0)
        case .rose: return Color(red: 1.0, green: 0.50, blue: 0.62)
        }
    }
}

// MARK: - The notch

/// The notch. One black shape whose size is animated with springs; what is inside
/// is laid out at its final size and revealed by the shape, the way the system's
/// own islands grow.
struct NotchView: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    /// The screen this notch is on (0 when there is only one).
    var display: CGDirectDisplayID = 0
    /// Goes up when a setting changes, so a settings preview is drawn again at once.
    var revision = 0
    /// Drawn inside the settings window, where there is nothing of its own to blur.
    var isPreview = false

    /// For the cover and the tab pill, which move between two places.
    @Namespace private var space

    var body: some View {
        let _ = revision
        let timerActive = services.timer.isActive
        let layout = NotchLayout(
            notch: notch, geometry: geometry, hasTrack: model.track.hasTrack, timerActive: timerActive,
            display: display
        )
        let scale = NotchGeometry.scale
        let settings = AppSettings.shared

        // Opening to the sides first: the height waits a moment for the width.
        let growing = layout.isOpen
        // The indicator has its own way of coming in.
        let peeking = layout.kind == .peek || (notch.peekClosing && !growing && layout.kind != .hud)
        let widthAnimation = growing ? NotchMotion.open
            : (layout.kind == .hud ? NotchMotion.hudIn : (peeking ? NotchMotion.peek : NotchMotion.close))
        let heightAnimation = (growing && settings.notchOpenStyle == .sidesFirst)
            ? NotchMotion.open.delay(NotchMotion.heightDelay)
            : widthAnimation

        ZStack(alignment: .top) {
            if layout.isOpen {
                OpenNotch(
                    notch: notch, model: model, services: services,
                    geometry: geometry, space: space, revision: revision
                )
                .frame(width: NotchGeometry.baseOpen.width, height: NotchGeometry.baseOpen.height)
                // Designed once, scaled to the size the user chose.
                .scaleEffect(scale, anchor: .top)
                .frame(width: NotchGeometry.openSize.width, height: NotchGeometry.openSize.height, alignment: .top)
                .transition(.blurReplace.combined(with: .opacity))
            } else {
                ClosedNotch(
                    notch: notch, model: model, services: services,
                    geometry: geometry, layout: layout, space: space, revision: revision
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .animation(layout.isOpen ? NotchMotion.open : (peeking ? NotchMotion.peek : NotchMotion.close), value: layout.kind)
        .frame(width: layout.body.width, alignment: .top)
        .animation(widthAnimation, value: layout.body.width)
        .frame(height: layout.body.height, alignment: .top)
        .animation(heightAnimation, value: layout.body.height)
        .padding(.horizontal, layout.ear)
        .animation(widthAnimation, value: layout.ear)
        .background(
            NotchSurfaceView(
                surface: settings.notchSurface, strength: settings.notchGlass,
                tint: NotchPalette.accent(model), isIdle: layout.kind == .idle,
                shape: NotchShape(topRadius: layout.ear, bottomRadius: layout.bottomRadius),
                drawsBlur: !isPreview
            )
        )
        .clipShape(NotchShape(topRadius: layout.ear, bottomRadius: layout.bottomRadius))
        .animation(widthAnimation, value: layout.bottomRadius)
        .shadow(color: .black.opacity(layout.isOpen ? 0.45 : 0), radius: 14, y: 6)
        .contentShape(Rectangle())
        .onHover { notch.hover($0, display: display) }
        .onTapGesture {
            // A notification is answered by opening its app; anything else, by
            // opening the notch.
            if let notification = notch.notification, !layout.isOpen {
                services.notifications.open(notification)
                notch.dismissNotification()
            } else {
                notch.hoverDisplay = display
                notch.open()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The notch as the window shows it: the same view, drawn again whenever a setting
/// changes, so what is chosen in the preferences shows at once and not after a
/// restart.
struct NotchRoot: View {
    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    var display: CGDirectDisplayID = 0
    @Bindable var revision = SettingsRevision.shared

    var body: some View {
        NotchView(
            notch: notch, model: model, services: services,
            geometry: geometry, display: display, revision: revision.value
        )
    }
}
