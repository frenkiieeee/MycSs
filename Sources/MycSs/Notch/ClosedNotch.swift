import SwiftUI
import UniformTypeIdentifiers

// MARK: - Closed

/// The closed notch: nothing when idle; the cover and the visualiser on its sides
/// while music plays; the title for a moment when the song changes; the volume or
/// the brightness when it changes; a notification when one arrives; the timer
/// while it runs.
struct ClosedNotch: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    let layout: NotchLayout
    let space: Namespace.ID
    var revision = 0

    var body: some View {
        let _ = revision
        let accent = NotchPalette.accent(model)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, NotchGeometry.sidePadding)
                Color.clear.frame(width: geometry.notch.width)
                trailing(accent: accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, NotchGeometry.sidePadding)
            }
            .frame(height: geometry.notch.height)

            // Under the cut-out: the title, in the style that drops down, or a
            // notification's text.
            if layout.kind == .peek, AppSettings.shared.notchPeekStyle == .drop {
                VStack(spacing: 0) {
                    Text(model.track.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(model.track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .frame(height: NotchGeometry.peekRow, alignment: .top)
                .transition(.blurReplace.combined(with: .opacity))
            }
            if layout.kind == .notification, let notification = notch.notification {
                VStack(spacing: 1) {
                    Text(notification.headline)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(notification.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .frame(height: NotchGeometry.notificationRow, alignment: .top)
                .transition(.blurReplace.combined(with: .opacity))
            }
        }
    }

    // MARK: Left side

    @ViewBuilder
    private var leading: some View {
        switch layout.kind {
        case .hud:
            if let hud = notch.hud {
                HUDIcon(hud: hud, shown: notch.hudShown, size: 15 * NotchGeometry.closedText)
                    .transition(AppSettings.shared.notchHUDEntrance.transition)
            }
        case .notification:
            if let notification = notch.notification {
                NotificationIcon(notification: notification, size: 24 * NotchGeometry.closedText)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        case .peek where AppSettings.shared.notchPeekStyle == .sides:
            // The title beside the cut-out.
            let boost = NotchGeometry.peekBoost
            HStack(spacing: 8) {
                cover(boost: boost)
                MarqueeText(text: model.track.title, size: 12.5 * NotchGeometry.closedText * boost, width: max(30, NotchGeometry.peekSide + NotchGeometry.wing - (30 * boost + 30) * NotchGeometry.closedText))
            }
            .transition(.blurReplace)
        case .wings, .peek:
            if services.timer.isActive, !(notch.isListening && model.track.hasTrack && AppSettings.shared.notchWings) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchPalette.accent(model))
                    .transition(.blurReplace)
            } else {
                cover
            }
        default:
            EmptyView()
        }
    }

    private var cover: some View { cover(boost: 1) }

    private func cover(boost: CGFloat) -> some View {
        CoverThumb(model: model, size: min(22 * NotchGeometry.closedText * boost, max(18, geometry.notch.height - 8)), radius: 6 * NotchGeometry.closedText * boost)
            .matchedGeometryEffect(id: "cover", in: space)
            .scaleEffect(model.isPlayingNow ? 1 : 0.86)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.isPlayingNow)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    // MARK: Right side

    @ViewBuilder
    private func trailing(accent: Color) -> some View {
        switch layout.kind {
        case .hud:
            if let hud = notch.hud {
                HUDValue(hud: hud, shown: notch.hudShown, barWidth: 52 * NotchGeometry.closedText - 8)
                    .transition(AppSettings.shared.notchHUDEntrance.transition)
            }
        case .notification:
            if let notification = notch.notification {
                Text(notification.appName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .transition(.blurReplace)
            }
        case .peek where AppSettings.shared.notchPeekStyle == .sides:
            let boost = NotchGeometry.peekBoost
            HStack(spacing: 8) {
                MarqueeText(
                    text: model.track.artist, size: 11 * boost, weight: .regular,
                    color: .white.opacity(0.6), width: max(24, NotchGeometry.peekSide + NotchGeometry.wing - (26 * boost + 30) * NotchGeometry.closedText)
                )
                Visualiser(active: model.isPlayingNow, tint: accent)
                    .frame(width: 14 * NotchGeometry.closedText * boost, height: 16 * NotchGeometry.closedText * boost)
            }
            .transition(.blurReplace)
        case .wings, .peek:
            if services.timer.isActive {
                TimerBadge(timer: services.timer, accent: accent)
                    .transition(.blurReplace)
            } else {
                Visualiser(active: model.isPlayingNow, tint: accent)
                    .frame(width: 20 * NotchGeometry.closedText, height: 16 * NotchGeometry.closedText)
                    .transition(.blurReplace)
            }
        default:
            EmptyView()
        }
    }
}

/// The icon of the app a notification came from, or the symbol of what MycSs
/// itself says.
struct NotificationIcon: View {
    let notification: NotchNotification
    let size: CGFloat

    var body: some View {
        if let symbol = notification.symbolName {
            Image(systemName: symbol)
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(brandYellow))
        } else if let icon = notification.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(.white.opacity(0.14)))
        }
    }
}

/// The time left on the timer, small, with its ring.
struct TimerBadge: View {
    @Bindable var timer: TimerModel
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(timer.text)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(timer.state == .paused ? .white.opacity(0.55) : .white)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
