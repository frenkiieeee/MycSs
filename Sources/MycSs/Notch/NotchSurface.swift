import AppKit
import SwiftUI

/// What the notch is made of (spec 016): plain black, or glass.
///
/// The glass is built in layers, from the bottom: black (so the notch still joins the
/// hardware one), a blur of what is behind the window, a dark veil (lighter the more
/// see-through the user asks for), a diagonal sheen, the accent colour for the tinted
/// kind, and a rim of light that fades towards the top.
///
/// The idle notch is always black: it has to melt into the cut-out of the screen. The
/// glass fades in as soon as the notch grows.
struct NotchSurfaceView: View {

    let surface: AppSettings.NotchSurface
    let strength: Double
    let tint: Color
    let isIdle: Bool
    let shape: AnyShape
    /// False on a screen without a notch that rests hidden: nothing is drawn at rest.
    var drawsBase = true
    /// A settings preview or a picture has no window of its own, so nothing to blur.
    var drawsBlur = true

    var body: some View {
        ZStack {
            Color.black
                .opacity(drawsBase ? 1 : 0)
                .animation(.smooth(duration: 0.3), value: drawsBase)
            if surface != .solid {
                glass
                    .opacity(isIdle ? 0 : 1)
                    .animation(.smooth(duration: 0.35), value: isIdle)
            }
        }
    }

    private var glass: some View {
        ZStack {
            if drawsBlur && !NotchSnapshot.isActive {
                BehindWindowBlur()
            }
            // The veil: the more the glass lets through, the lighter it is.
            Color.black.opacity(0.80 - 0.62 * strength)
            // A sheen from the top left, like light on a curved pane.
            LinearGradient(
                colors: [.white.opacity(0.20), .white.opacity(0.03), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if surface == .tinted {
                LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .blendMode(.plusLighter)
            }
        }
        .overlay {
            shape
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.42)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
    }
}

/// The blur of whatever is behind the window. `NSVisualEffectView` does it for real,
/// without any screen recording permission. It stays active even though the notch's
/// window is never the key window.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
