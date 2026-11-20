import SwiftUI
import UniformTypeIdentifiers

// MARK: - The volume and the brightness

extension NotchHUD {
    var symbol: String {
        switch kind {
        case .volume: return muted || value <= 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return "sun.max.fill"
        case .keyboard: return "keyboard.fill"
        }
    }

    /// What it is called.
    var title: String {
        switch kind {
        case .volume: return "Volumen"
        case .brightness: return "Brillo"
        case .keyboard: return "Luz del teclado"
        }
    }

        /// What the bar shows: nothing when muted.
    var shown: CGFloat { shownValue }
    var percent: Int { Int((shown * 100).rounded()) }
}

/// The icon of the indicator: the speaker, the sun, or a keyboard with rays of light.
struct HUDIcon: View {
    let hud: NotchHUD
    let shown: CGFloat
    var size: CGFloat = 15

    var body: some View {
        switch hud.kind {
        case .keyboard:
            KeyboardLightIcon(level: shown, size: size)
        case .volume, .brightness:
            Image(systemName: hud.symbol, variableValue: Double(shown))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

/// A keyboard with rays of light over it. The rays grow and brighten with the
/// level and go out at zero, so the icon says "keyboard" and shows how lit it is.
struct KeyboardLightIcon: View {
    /// From 0 to 1; it travels with the indicator, so the rays glide too.
    let level: CGFloat
    let size: CGFloat

    var body: some View {
        let lit = min(max(level, 0), 1)
        ZStack {
            Image(systemName: "keyboard.fill")
                .font(.system(size: size * 1.2, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: size * 0.36)
            Image(systemName: lit < 0.05 ? "light.min" : "light.max")
                .font(.system(size: size * 0.92, weight: .bold))
                .foregroundStyle(.white)
                .opacity(0.2 + 0.8 * lit)
                .scaleEffect(0.82 + 0.28 * lit, anchor: .bottom)
                .offset(y: -size * 0.42)
        }
        .frame(width: size * 1.75, height: size * 1.6)
        .accessibilityLabel("Luz del teclado")
    }
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
