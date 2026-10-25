import SwiftUI

/// The animated background behind the lyrics.
///
/// Three modes, matching the reference screenshots:
///
/// - **gradient**: a `MeshGradient` built from the artwork's colours, rotating
///   slowly.
/// - **glow**: a near-black backdrop with soft colour halos that drift behind
///   the lyrics, radiating from the active word. This is the "resplandor" look.
/// - **dark**: flat black, for maximum legibility.
struct BackgroundView: View {

    enum Mode: String, CaseIterable {
        case gradient
        case glow
        case dark

        var title: String {
            switch self {
            case .gradient: return "Gradiente del álbum"
            case .glow: return "Resplandor de color"
            case .dark: return "Negro"
            }
        }
    }

    var theme: Theme
    var mode: Mode = .gradient
    /// The animation speed multiplier.
    var intensity: Double = 1.0
    /// The position of the active word, used to place the glow.
    var activeWordPosition: UnitPoint = .center

    var body: some View {
        switch mode {
        case .gradient:
            gradient
        case .glow:
            glow
        case .dark:
            Color.black
        }
    }

    // MARK: - Gradient

    private var gradient: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // One full turn every 40 seconds, scaled by the intensity.
            let angle = time * (2 * .pi / 40) * max(intensity, 0.1)
            let offset = sin(angle) * 0.18
            let offset2 = cos(angle * 0.7) * 0.14

            // The locations and colours are built separately: writing them inline
            // makes the type checker take too long to resolve the expression.
            let locations: [SIMD2<Float>] = [
                .init(0, 0), .init(0.5 + Float(offset), 0), .init(1, 0),
                .init(0, 0.5 + Float(offset2)), .init(0.5, 0.5), .init(1, 0.5 - Float(offset)),
                .init(0, 1), .init(0.5 - Float(offset2), 1), .init(1, 1),
            ]
            let colours: [Color] = [
                theme.backgroundDeep.color,
                theme.backgroundMid.color,
                theme.backgroundDeep.color,
                theme.backgroundMid.color,
                theme.accent.color.opacity(0.35),
                theme.backgroundDeep.color,
                theme.backgroundDeep.color,
                theme.secondary.color.opacity(0.25),
                theme.backgroundDeep.color,
            ]

            MeshGradient(
                width: 3,
                height: 3,
                locations: .points(locations),
                colors: .colors(colours)
            )
        }
        .drawingGroup()
    }

    // MARK: - Glow

    private var glow: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            ZStack {
                Color.black

                // Halos that drift on slow, different paths.
                halo(
                    colour: theme.accent.color,
                    radius: 0.55,
                    phase: time * 0.09 * max(intensity, 0.1),
                    x: 0.5 + 0.28 * sin(time * 0.11 * max(intensity, 0.1)),
                    y: 0.42 + 0.20 * cos(time * 0.07 * max(intensity, 0.1))
                )
                halo(
                    colour: theme.secondary.color,
                    radius: 0.42,
                    phase: time * 0.13 * max(intensity, 0.1) + 2.1,
                    x: 0.62 + 0.22 * cos(time * 0.08 * max(intensity, 0.1)),
                    y: 0.62 + 0.18 * sin(time * 0.05 * max(intensity, 0.1) + 1.2)
                )
                halo(
                    colour: theme.accent.color,
                    radius: 0.30,
                    phase: time * 0.17 * max(intensity, 0.1) + 4.3,
                    x: 0.34 + 0.24 * sin(time * 0.13 * max(intensity, 0.1) + 0.7),
                    y: 0.30 + 0.16 * cos(time * 0.10 * max(intensity, 0.1))
                )
            }
        }
        .drawingGroup()
    }

    /// One soft radial halo.
    private func halo(
        colour: Color,
        radius: Double,
        phase: Double,
        x: Double,
        y: Double
    ) -> some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [colour.opacity(0.55), colour.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * radius * 0.5
                    )
                )
                .frame(width: size * radius, height: size * radius)
                .position(
                    x: geometry.size.width * x,
                    y: geometry.size.height * y
                )
                .blur(radius: 40)
                .blendMode(.plusLighter)
        }
    }
}
