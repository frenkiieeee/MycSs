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

// MARK: - Shape

/// The shape of the notch: flat at the top, rounded at the bottom, and with the
/// top corners curving **outwards** into the menu bar, the way the hardware
/// notch itself blends into it.
///
/// The body is `topRadius` narrower on each side than the rectangle it is drawn
/// in; those margins are the curved corners.
struct NotchShape: Shape {

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(topRadius, 0)
        let b = min(max(bottomRadius, 0), max(rect.height - t, 0))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control: CGPoint(x: rect.minX + t, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + t, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - t, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - t, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Debug probes

/// Set while a capture is being drawn. The renderer that makes the captures
/// paints a warning square over any drop target and skips scroll views, so both
/// are left out of captures. It is never set in the running app.
enum NotchSnapshot {
    nonisolated(unsafe) static var isActive = false
}

/// Where the controls are, recorded only for the self test, which clicks on them.
enum NotchProbe {
    nonisolated(unsafe) static var isOn = false
    nonisolated(unsafe) static var frames: [String: CGRect] = [:]
}

extension View {
    /// Records the frame of a control for the self test. Does nothing otherwise.
    @ViewBuilder
    func probe(_ id: String) -> some View {
        if NotchProbe.isOn {
            background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { NotchProbe.frames[id] = frame }
                        .onChange(of: frame) { _, new in NotchProbe.frames[id] = new }
                }
            }
        } else {
            self
        }
    }
}

// MARK: - Style

/// The colours of the notch, from the user's choice.
enum NotchPalette {
    @MainActor
    static func accent(_ model: LyricsViewModel) -> Color {
        switch AppSettings.shared.notchAccent {
        case .album: return model.theme.accent.color
        case .yellow: return brandYellow
        case .white: return .white
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
        .background(Color.black)
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

// MARK: - Shared pieces

/// A record that turns while the music plays, kept across redraws so a pause does
/// not send it back to the start.
@MainActor
final class VinylSpin {
    static let shared = VinylSpin()
    private var angle = 0.0
    private var last: Date?

    func angle(at date: Date, playing: Bool) -> Double {
        defer { last = date }
        if playing, let last { angle += min(date.timeIntervalSince(last), 0.2) * 42 }
        return angle.truncatingRemainder(dividingBy: 360)
    }
}

/// The album cover. When there is none (a song without artwork, or one that has
/// not loaded yet) a note on a grey square takes its place. It can be a square
/// with rounded corners or a record that turns.
struct CoverThumb: View {

    @Bindable var model: LyricsViewModel
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        if AppSettings.shared.notchCoverShape == .vinyl {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.isPlayingNow)) { timeline in
                let angle = VinylSpin.shared.angle(at: timeline.date, playing: model.isPlayingNow)
                picture
                    .clipShape(Circle())
                    .overlay {
                        // The hole of the record.
                        Circle().fill(.black).frame(width: size * 0.16, height: size * 0.16)
                        Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1).frame(width: size * 0.16, height: size * 0.16)
                    }
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .rotationEffect(.degrees(angle))
            }
        } else {
            picture.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private var picture: some View {
        Group {
            if let image = model.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// The visualiser, in the style the user chose. By default it moves on its own
/// while the music plays; with the real-rhythm option on (and the audio tap
/// running) it follows the sound. It only shows on the outside of the closed
/// notch; open, it is not drawn.
struct Visualiser: View {
    let active: Bool
    let tint: Color

    /// Thin bars, close together.
    private static let barWidth: CGFloat = 2
    private static let gap: CGFloat = 2.2

    var body: some View {
        let style = AppSettings.shared.notchVisualizerStyle
        let reactor = AudioReactor.shared
        let real = AppSettings.shared.notchReactive && reactor.isRunning && active
        let levels = real ? reactor.levels : nil

        switch style {
        case .off:
            EmptyView()
        case .bars:
            if let levels { bars(levels: levels) } else { simulatedBars }
        case .wave:
            wave(levels: levels)
        case .dots:
            dots(levels: levels)
        }
    }

    private func bars(levels: [Float]) -> some View {
        HStack(alignment: .center, spacing: Self.gap) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: Self.barWidth, height: 16 * (0.14 + 0.86 * CGFloat(levels[min(index, levels.count - 1)])))
            }
        }
        .animation(.linear(duration: 0.05), value: levels)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var simulatedBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: Self.gap) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = t * (2.6 + Double(index) * 0.9) + Double(index) * 1.9
                    let level = active ? 0.3 + 0.7 * abs(sin(phase)) : 0.2
                    Capsule()
                        .fill(tint)
                        .frame(width: Self.barWidth, height: 16 * level)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    /// A line that undulates, taller with louder music.
    private func wave(levels: [Float]?) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = levels.map { CGFloat($0.reduce(0, +) / Float(max($0.count, 1))) } ?? 0.55
            Canvas { context, size in
                var path = Path()
                let amplitude = size.height * 0.42 * (active ? (0.35 + 0.65 * energy) : 0.12)
                let steps = 24
                for step in 0...steps {
                    let x = size.width * CGFloat(step) / CGFloat(steps)
                    let phase = CGFloat(step) / CGFloat(steps) * .pi * 3
                    let y = size.height / 2 + sin(phase + CGFloat(t) * 6) * amplitude * sin(CGFloat(step) / CGFloat(steps) * .pi)
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Three dots that bounce one after the other.
    private func dots(levels: [Float]?) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = levels.map { CGFloat($0.reduce(0, +) / Float(max($0.count, 1))) } ?? 0.6
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let bounce = active ? abs(sin(t * 4 + Double(index) * 0.9)) * (0.4 + 0.6 * energy) : 0
                    Circle()
                        .fill(tint)
                        .frame(width: 4.5, height: 4.5)
                        .offset(y: -CGFloat(bounce) * 5)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// The press of a control in the notch: it gives a little and comes back.
struct NotchPress: ButtonStyle {
    var scale: CGFloat = 0.84

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A line of text that scrolls when it does not fit, like a car radio.
struct MarqueeText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold
    var color: Color = .white
    let width: CGFloat

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: nsWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private var nsWeight: NSFont.Weight {
        switch weight {
        case .bold, .heavy, .black: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        default: return .regular
        }
    }

    var body: some View {
        let measured = textWidth
        if measured <= width {
            Text(text)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        } else {
            let gap: CGFloat = 28
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                // A pause at the start, then a slow slide.
                let t = timeline.date.timeIntervalSinceReferenceDate
                let cycle = Double(measured + gap) / 28
                let phase = (t.truncatingRemainder(dividingBy: cycle + 1.4)) - 1.4
                let offset = -CGFloat(max(phase, 0)) * 28
                HStack(spacing: gap) {
                    Text(text)
                    Text(text)
                }
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .frame(width: width, alignment: .leading)
                .clipped()
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
        }
    }
}

// MARK: - The volume and the brightness

private extension NotchHUD {
    var symbol: String {
        switch kind {
        case .volume: return muted || value <= 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        }
    }

        /// What the bar shows: nothing when muted.
    var shown: CGFloat { shownValue }
    var percent: Int { Int((shown * 100).rounded()) }
}

/// The volume or brightness as a thin bar.
struct HUDBar: View {
    let value: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.22))
            Capsule().fill(.white).frame(width: max(width * value, 0))
        }
        .frame(width: width, height: 5)
    }
}

/// A bar with a knob that slides along it.
struct HUDSlider: View {
    let value: CGFloat
    let width: CGFloat

    var body: some View {
        let knob: CGFloat = 11
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.22)).frame(height: 3)
            Capsule().fill(.white.opacity(0.9)).frame(width: max((width - knob) * value + knob / 2, 0), height: 3)
            Circle()
                .fill(.white)
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .offset(x: (width - knob) * value)
        }
        .frame(width: width, height: knob)
    }
}

/// The volume or brightness as a ring.
struct HUDRing: View {
    let value: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.22), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: max(value, 0.001))
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

/// Ten little bars that fill one after the other, the last one partly.
struct HUDSegments: View {
    let value: CGFloat
    let width: CGFloat

    var body: some View {
        let count = 10
        let gap: CGFloat = 2
        let each = (width - gap * CGFloat(count - 1)) / CGFloat(count)
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { index in
                let fill = min(max(value * CGFloat(count) - CGFloat(index), 0), 1)
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(height: 4 + 8 * fill).opacity(0.25 + 0.75 * fill)
                }
                .frame(width: each, height: 12)
            }
        }
    }
}

/// A number that counts through every value between the old one and the new one.
struct CountingNumber: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
    }
}

/// What the indicator shows next to its icon, in the user's style: a bar, a
/// slider, a ring or segments, and the number (or not).
///
/// It is drawn from `shown`, the value that travels, and not from the real one:
/// that is what makes the bar, the knob, the ring and the number glide.
struct HUDValue: View {
    let hud: NotchHUD
    let shown: CGFloat
    var barWidth: CGFloat = 52

    var body: some View {
        let settings = AppSettings.shared
        let style = settings.notchHUDStyle
        let numbers = settings.notchHUDNumber
        let size: CGFloat = style == .minimal ? 14 : 11.5
        HStack(spacing: 7) {
            switch style {
            case .bar: HUDBar(value: shown, width: barWidth)
            case .slider: HUDSlider(value: shown, width: barWidth)
            case .ring: HUDRing(value: shown, size: 17)
            case .segments: HUDSegments(value: shown, width: barWidth)
            case .minimal: EmptyView()
            }
            switch numbers {
            case .hidden:
                EmptyView()
            case .counting:
                CountingNumber(value: Double(shown * 100))
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 24, alignment: .trailing)
            case .wheel:
                Text("\(hud.percent)")
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 24, alignment: .trailing)
                    .contentTransition(.numericText(value: Double(hud.percent)))
                    .animation(NotchMotion.hudValue, value: hud.percent)
            case .fixed:
                Text("\(hud.percent)")
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 24, alignment: .trailing)
            }
        }
    }
}

extension AppSettings.NotchHUDEntrance {
    /// How the indicator's pieces come in and go.
    var transition: AnyTransition {
        switch self {
        case .grow: return AnyTransition(.blurReplace)
        case .pop: return .scale(scale: 0.3).combined(with: .opacity)
        case .slide: return .move(edge: .top).combined(with: .opacity)
        case .fade: return .opacity
        }
    }
}

// MARK: - Closed

/// The closed notch: nothing when idle; the cover and the visualiser on its sides
/// while music plays; the title for a moment when the song changes; the volume or
/// the brightness when it changes; a notification when one arrives; the timer
/// while it runs.
private struct ClosedNotch: View {

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
                Image(systemName: hud.symbol, variableValue: Double(notch.hudShown))
                    .font(.system(size: 15 * NotchGeometry.closedText, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
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
private struct TimerBadge: View {
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

// MARK: - Open

private struct OpenNotch: View {

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
private struct Header: View {

    @Bindable var notch: NotchModel
    @Bindable var model: LyricsViewModel
    let services: NotchServices
    let geometry: NotchGeometry
    let space: Namespace.ID

    var body: some View {
        HStack(spacing: 2) {
            tab(.home, symbol: "house.fill")
            tab(.shelf, symbol: "tray.fill")

            Spacer(minLength: geometry.notch.width)

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
                        Text(notification.headline)
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
        .frame(height: geometry.notch.height)
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
private struct HomePage: View {

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

private struct MusicBlock: View {

    @Bindable var model: LyricsViewModel
    let space: Namespace.ID

    var body: some View {
        if model.track.hasTrack {
            HStack(alignment: .top, spacing: 14) {
                CoverThumb(model: model, size: 116, radius: 16)
                    .matchedGeometryEffect(id: "cover", in: space)
                    .shadow(color: NotchPalette.accent(model).opacity(0.4), radius: 16)
                    .overlay(alignment: .bottomTrailing) {
                        PlayerBadge(source: model.track.source)
                            .offset(x: 6, y: 6)
                    }
                    // Steps back when paused, like the cover in the lyrics.
                    .scaleEffect(model.isPlayingNow ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model.isPlayingNow)
                    // A new song brings its own cover.
                    .id(model.track.trackKey)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: model.track.title, size: 14.5, width: HomeLayout.musicWidth - 130)
                        MarqueeText(
                            text: model.track.artist, size: 12, weight: .regular,
                            color: .white.opacity(0.55), width: HomeLayout.musicWidth - 130
                        )
                    }
                    .id(model.track.trackKey)
                    .transition(.blurReplace)
                    Spacer(minLength: 2)
                    SeekBar(model: model)
                    Transport(model: model)
                }
                .frame(height: 116)
            }
            .animation(NotchMotion.swap, value: model.track.trackKey)
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

/// The icon of the player the song comes from, on the corner of the cover.
private struct PlayerBadge: View {

    let source: NowPlaying.Source

    private var icon: NSImage? {
        let bundle: String
        switch source {
        case .spotify: bundle = "com.spotify.client"
        case .appleMusic: bundle = "com.apple.Music"
        case .none: return nil
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        }
    }
}

/// The progress of the song. A click or a drag on it jumps there.
private struct SeekBar: View {

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
private struct Transport: View {

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
