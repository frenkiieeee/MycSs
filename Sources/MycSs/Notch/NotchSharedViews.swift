import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared pieces

/// How often the closed notch's small animations (the turning record and the bars) are
/// drawn. They share it on purpose: each one wakes the whole notch window, so two
/// different rates meant up to fifty redraws a second for a few pixels of movement.
enum NotchFrame {
    static let interval: TimeInterval = 1.0 / 20.0
}

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
            TimelineView(.animation(minimumInterval: NotchFrame.interval, paused: !model.isPlayingNow)) { timeline in
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

    /// The cover. A new song's cover fades in over the old one, a little bigger and
    /// settling, like the lyrics screen does; it follows the song change setting.
    private var picture: some View {
        let kind = AppSettings.shared.songTransition
        let fade = model.artworkOpacity
        let moves = kind == .glide || kind == .cinematic
        return ZStack {
            if let image = model.artwork {
                // The old cover stays underneath while the new one comes in.
                if fade < 1, let previous = model.previousArtwork {
                    Image(nsImage: previous)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .scaleEffect(moves ? 1 - 0.05 * fade : 1)
                        .blur(radius: kind == .cinematic ? 3 * fade : 0)
                }
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .scaleEffect(moves ? 1 + 0.08 * (1 - fade) : 1)
                    .blur(radius: kind == .cinematic ? 4 * (1 - fade) : 0)
                    .opacity(fade)
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
        .clipped()
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
        TimelineView(.animation(minimumInterval: NotchFrame.interval, paused: !active)) { timeline in
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
        TimelineView(.animation(minimumInterval: NotchFrame.interval, paused: !active)) { timeline in
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
        TimelineView(.animation(minimumInterval: NotchFrame.interval, paused: !active)) { timeline in
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
