import SwiftUI

/// The hint shown when the mouse moves.
///
/// The overlay covers the lock screen, so the area where the password is typed
/// is hidden behind it. When the pointer moves, this view fades in: a soft
/// panel marking where to type, and a legend at the bottom explaining what to
/// do.
///
/// It never takes the click itself: the overlay is click-through, so the click
/// reaches the real password field underneath.
struct PasswordHintView: View {

    /// How visible the hint is, from 0 (hidden) to 1 (fully shown).
    var reveal: Double

    /// The colour of the accent, so the hint matches the theme.
    var accent: Color

    var body: some View {
        VStack(spacing: 0) {
            // The marker where the password goes: centred on the screen, so it
            // points at the real password field underneath the overlay.
            Spacer()
            passwordArea
            Spacer()

            // The legend along the bottom.
            legend
        }
        .opacity(reveal)
        .allowsHitTesting(false)
    }

    // MARK: - Password area

    private var passwordArea: some View {
        VStack(spacing: 14) {
            // A row of dots, the way macOS shows the password field.
            HStack(spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 11, height: 11)
                }
            }

            Text("Escribí tu contraseña para desbloquear")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                Text("MycSs")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.65))

            Text("⌘L para bloquear · las letras siguen con la música")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 26)
    }
}
