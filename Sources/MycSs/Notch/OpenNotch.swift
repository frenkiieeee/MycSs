import SwiftUI
import UniformTypeIdentifiers

// MARK: - Open

struct OpenNotch: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    let space: Namespace.ID
    var revision = 0

    var body: some View {
        let _ = revision
        VStack(spacing: 0) {
            Header(notch: notch, model: model, services: services, geometry: geometry, space: space)

            ZStack {
                switch notch.tab {
                case .home:
                    HomePage(notch: notch, model: model, services: services, space: space)
                        .transition(.blurReplace)
                case .shelf:
                    ShelfPage(shelf: services.shelf, notch: notch)
                        .transition(.blurReplace)
                }
            }
            .animation(NotchMotion.swap, value: notch.tab)
            .padding(.horizontal, 26)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The strip at the top of the open notch, on both sides of the cut-out: the
/// tabs on the left; on the right the settings, or, while it lasts, the volume or
/// a notification.
struct Header: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    let space: Namespace.ID

    var body: some View {
        HStack(spacing: 2) {
            tab(.home, symbol: "house.fill")
            tab(.shelf, symbol: "tray.fill")

            Spacer(minLength: geometry.contentGap)

            if let hud = notch.hud {
                // The value, in the strip, where it can be seen while the notch is open.
                HStack(spacing: 8) {
                    Image(systemName: hud.symbol, variableValue: Double(notch.hudShown))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    HUDValue(hud: hud, shown: notch.hudShown, barWidth: 84)
                }
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.14)))
                .transition(AppSettings.shared.notchHUDEntrance.transition)
            } else if let notification = notch.notification {
                Button {
                    services.notifications.open(notification)
                    notch.dismissNotification()
                } label: {
                    HStack(spacing: 7) {
                        NotificationIcon(notification: notification, size: 18)
                        Text(notification.shownHeadline)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(.white.opacity(0.14)))
                }
                .buttonStyle(NotchPress(scale: 0.95))
                .transition(.blurReplace.combined(with: .opacity))
                .probe("notificationPill")
            } else {
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 34, height: 26)
                }
                .buttonStyle(NotchPress())
                .transition(.blurReplace)
                .probe("settings")
            }
        }
        .padding(.horizontal, 22)
        .frame(height: geometry.openHeader)
        .animation(NotchMotion.swap, value: notch.notification)
        .animation(NotchMotion.swap, value: notch.tab)
    }

    private func tab(_ tab: NotchTab, symbol: String) -> some View {
        let active = notch.tab == tab
        return Button {
            notch.tab = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 0.98 : 0.42))
                .frame(width: 42, height: 26)
                .background {
                    // One pill that slides from tab to tab.
                    if active {
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .matchedGeometryEffect(id: "tabPill", in: space)
                    }
                }
        }
        .buttonStyle(NotchPress(scale: 0.92))
        .probe("tab.\(tab.rawValue)")
    }
}

// MARK: - Home

/// Where the content of the home page goes: 60 % for the music, 40 % for the
/// widget.
enum HomeLayout {
    static let side: CGFloat = 26
    static let gap: CGFloat = 20
    static var content: CGFloat { NotchGeometry.baseOpen.width - side * 2 }
    static var musicWidth: CGFloat { (content - gap) * 0.6 }
    static var widgetWidth: CGFloat { (content - gap) * 0.4 }
}

/// Music on the left (60 %), a widget on the right (40 %).
struct HomePage: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices

    let space: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: HomeLayout.gap) {
            MusicBlock(model: model, space: space)
                .frame(width: HomeLayout.musicWidth, alignment: .topLeading)
            if AppSettings.shared.notchCalendar {
                WidgetBlock(notch: notch, services: services)
                    .frame(width: HomeLayout.widgetWidth, alignment: .topLeading)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct MusicBlock: View {

    @Bindable var model: LyricsViewModel
    let space: Namespace.ID

    var body: some View {
        if model.track.hasTrack {
            HStack(alignment: .top, spacing: 14) {
                CoverThumb(model: model, size: 116, radius: 16)
                    .matchedGeometryEffect(id: "cover", in: space)
                    .shadow(color: NotchPalette.accent(model).opacity(0.4), radius: 16)
                    .overlay(alignment: .bottomTrailing) {
                        PlayerBadge(model: model)
                            .offset(x: 6, y: 6)
                    }
                    // Steps back when paused, like the cover in the lyrics.
                    .scaleEffect(model.isPlayingNow ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model.isPlayingNow)
                    // A new song brings its own cover: it fades in over the old one (see
                    // `CoverThumb`) and the whole cover gives a small beat.
                    .scaleEffect(1 + 0.05 * sin(model.artworkOpacity * .pi))

                VStack(alignment: .leading, spacing: 0) {
                    // The title and the artist are replaced with their own movement. Each song
                    // is a new view (`id`), so a quick run of changes keeps animating: every
                    // one takes the previous one's place instead of waiting for it.
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(text: model.track.title, size: 14.5, width: HomeLayout.musicWidth - 130)
                            MarqueeText(
                                text: model.track.artist, size: 12, weight: .regular,
                                color: .white.opacity(0.55), width: HomeLayout.musicWidth - 130
                            )
                        }
                        .id(model.track.trackKey)
                        .transition(AppSettings.shared.songTransition.textTransition)
                    }
                    .frame(width: HomeLayout.musicWidth - 130, alignment: .topLeading)
                    .animation(
                        AppSettings.shared.songTransition == .off
                            ? nil : .smooth(duration: max(0.25, AppSettings.shared.songTransitionSeconds * 0.7)),
                        value: model.track.trackKey
                    )
                    Spacer(minLength: 2)
                    SeekBar(model: model)
                    Transport(model: model)
                }
                .frame(height: 116)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No suena nada ahora mismo")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The icon of the player the song comes from, on the corner of the cover: the app,
/// or the browser for a tab. With more than one player that has something, it is a
/// button that moves to the next one (spec 014).
struct PlayerBadge: View {

    @Bindable var model: LyricsViewModel

    private var icon: NSImage? {
        let bundle: String
        switch model.track.source {
        case .spotify: bundle = "com.spotify.client"
        case .appleMusic: bundle = "com.apple.Music"
        case .browser: bundle = model.track.appBundleID
        case .none: return nil
        }
        guard !bundle.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var canSwitch: Bool {
        model.availableSources.contains { $0 != model.track.source }
    }

    var body: some View {
        if let icon {
            Button {
                guard canSwitch else { return }
                NotchHaptics.tick()
                model.cycleSource()
            } label: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                    .overlay(alignment: .topTrailing) {
                        if canSwitch {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 7.5, weight: .heavy))
                                .foregroundStyle(.black)
                                .frame(width: 13, height: 13)
                                .background(Circle().fill(.white))
                                .offset(x: 4, y: -4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentTransition(.opacity)
            }
            .buttonStyle(NotchPress(scale: 0.85))
            .help(canSwitch ? "Pasar al siguiente reproductor" : "")
            .probe("playerBadge")
            .animation(NotchMotion.swap, value: canSwitch)
            .animation(NotchMotion.swap, value: model.track.source)
        }
    }
}

/// The progress of the song. A click or a drag on it jumps there.
struct SeekBar: View {

    @Bindable var model: LyricsViewModel

    var body: some View {
        let duration = max(model.track.durationSec, 0)
        let position = duration > 0 ? min(max(model.position, 0), duration) : 0
        let fraction = duration > 0 ? position / duration : 0

        VStack(spacing: 1) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.95)).frame(width: proxy.size.width * fraction)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard duration > 0, proxy.size.width > 0 else { return }
                            let target = min(max(value.location.x / proxy.size.width, 0), 1)
                            model.perform(.seek(target * duration))
                        }
                )
            }
            .frame(height: 14)
            .probe("seek")

            HStack {
                Text(Self.format(position))
                Spacer()
                Text(Self.format(duration))
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Previous, play or pause, next.
struct Transport: View {

    @Bindable var model: LyricsViewModel

    var body: some View {
        HStack(spacing: 0) {
            button("backward.fill", size: 17, id: "previous") { model.perform(.previous) }
            button(model.isPlayingNow ? "pause.fill" : "play.fill", size: 26, id: "playPause") {
                model.perform(.playPause)
            }
            .shadow(color: NotchPalette.accent(model).opacity(model.isPlayingNow ? 0.7 : 0), radius: 10)
            button("forward.fill", size: 17, id: "next") { model.perform(.next) }
        }
        .frame(maxWidth: .infinity)
    }

    private func button(
        _ symbol: String, size: CGFloat, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(NotchPress())
        .probe(id)
    }
}
