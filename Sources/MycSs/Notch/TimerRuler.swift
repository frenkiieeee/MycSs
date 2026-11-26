import SwiftUI

/// The timer's time picker as a ruler (spec 016): drag it sideways, one mark a minute
/// and a long mark every five, and press "Iniciar". The way the iPhone's island asks.
struct TimerRuler: View {

    @Bindable var timer: TimerModel

    static let pointsPerMinute: CGFloat = 9
    static let range = 1...180
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.35)

    /// The minutes after dragging `translation` points from `start`: dragging to the
    /// left moves the ruler left, so the number goes up.
    static func minutes(from start: Int, translation: CGFloat) -> Int {
        min(max(start - Int((translation / pointsPerMinute).rounded()), range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(spacing: 5) {
            ruler
            HStack(alignment: .center, spacing: 8) {
                Button {
                    timer.start(minutes: timer.rulerMinutes)
                    NotchHaptics.tick()
                } label: {
                    Text("Iniciar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Self.amber)
                        .padding(.horizontal, 13)
                        .frame(height: 26)
                        .background(Capsule().fill(Self.amber.opacity(0.2)))
                }
                .buttonStyle(NotchPress(scale: 0.93))
                .probe("timer.rulerStart")

                Spacer(minLength: 0)

                Text(TimerModel.format(TimeInterval(timer.rulerMinutes * 60)))
                    .font(.system(size: 26, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(Self.amber)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.top, 2)
        .transition(.blurReplace)
    }

    private var ruler: some View {
        let minutes = timer.rulerMinutes
        return VStack(spacing: 1) {
            Canvas { context, size in
                let middle = size.width / 2
                let span = Int(middle / Self.pointsPerMinute) + 2
                for step in -span...span {
                    let value = minutes + step
                    guard Self.range.contains(value) else { continue }
                    let x = middle + CGFloat(step) * Self.pointsPerMinute
                    let major = value % 5 == 0
                    let selected = step == 0
                    // Fades towards the edges, like a dial.
                    let fade = max(0, 1 - pow(abs(x - middle) / middle, 2.2))
                    let height: CGFloat = selected ? 22 : (major ? 17 : 10)
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: size.height))
                    tick.addLine(to: CGPoint(x: x, y: size.height - height))
                    context.stroke(
                        tick,
                        with: .color((selected ? Color.white : (major ? Self.amber : Self.amber.opacity(0.55))).opacity(fade)),
                        style: StrokeStyle(lineWidth: selected ? 2.4 : (major ? 2 : 1), lineCap: .round)
                    )
                    if major && !selected {
                        context.draw(
                            Text("\(value)").font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.55 * fade)),
                            at: CGPoint(x: x, y: size.height - height - 8)
                        )
                    }
                }
            }
            .frame(height: 44)
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7))
                .foregroundStyle(Self.amber)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = timer.rulerDragStart ?? timer.rulerMinutes
                    timer.rulerDragStart = start
                    let next = Self.minutes(from: start, translation: drag.translation.width)
                    if next != timer.rulerMinutes {
                        timer.rulerMinutes = next
                        NotchHaptics.tick()
                    }
                }
                .onEnded { _ in timer.rulerDragStart = nil }
        )
        .probe("timer.ruler")
    }
}
