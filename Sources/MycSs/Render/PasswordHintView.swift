import SwiftUI

/// The hint shown when the mouse moves.
///
/// The overlay covers the lock screen, so the area where the password is typed
/// is hidden behind it. When the pointer moves, this view fades in at the
/// bottom left of the screen, showing the field, the name of the app and the
/// hint of what to type.
///
/// **While the user types the hint stays**, and the field shows the dots of
/// what is being written: the overlay covers the real field, so without this
/// the user would have no idea whether their keystrokes were going anywhere.
/// The eye button at the right of the field shows the text itself.
///
/// It never takes the click itself: the overlay is click-through, so the click
/// reaches the real password field underneath.
struct PasswordHintView: View {

    /// How visible the hint is, from 0 (hidden) to 1 (fully shown).
    var reveal: Double

    /// Whether the user is typing.
    var isTyping: Bool = false

    /// What the user has written, when the app can tell which keys they were.
    var typedPassword: String = ""

    /// How many keys the user has pressed.
    ///
    /// The lock screen hides which keys are pressed, but not how many, so the
    /// dots are counted there.
    var pressedKeys: Int = 0

    /// Whether the app knows the characters that were written.
    var knowsCharacters: Bool = false

    /// Whether the text is shown as it was written.
    var revealsPassword: Bool = false

    /// The colour of the accent, so the hint matches the theme.
    var accent: Color

    /// The margin on the left, the same one the cover and the title use.
    var sideMargin: CGFloat = 0

    /// Called with the place of the eye button, in screen coordinates.
    var onRevealRect: ((CGRect) -> Void)?

    /// The width of the field.
    private let fieldWidth: CGFloat = 210
    /// The height of the field.
    private let fieldHeight: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // The hint, in the bottom left corner, in line with the cover
                // and the title.
                VStack(alignment: .leading, spacing: 10) {
                    passwordField

                    Text("Ingresa tu contraseña")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("MycSs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 6)
                }
                .padding(.leading, sideMargin)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(reveal)
        .allowsHitTesting(false)
    }

    // MARK: - Password field

    /// The field: a capsule with the dots of what is being written and the eye
    /// button at its right end.
    private var passwordField: some View {
        ZStack(alignment: .leading) {
            // The field itself: rounded ends, the way Apple draws them.
            Capsule(style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            .white.opacity(isTyping ? 0.75 : 0.45),
                            lineWidth: 1
                        )
                }

            // What has been written, and the caret at the end of it.
            HStack(spacing: 3) {
                ForEach(Array(masked.enumerated()), id: \.offset) { _, character in
                    Text(String(character))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                caret
            }
            .padding(.leading, 14)
            .padding(.trailing, 34)

            // The eye, at the right end of the field. It only appears when
            // there is a text to uncover: the lock screen hides which keys are
            // pressed, and there would be nothing to show.
            if knowsCharacters {
                eyeButton
                    .offset(x: fieldWidth - 30)
            }
        }
        .frame(width: fieldWidth, height: fieldHeight)
        .background {
            // The place of the eye in screen coordinates, so that the click
            // can be noticed: the overlay is click-through and never sees it
            // itself.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { reportEye(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        reportEye(frame)
                    }
            }
        }
    }

    /// The caret of the field.
    ///
    /// It blinks the way the one of a real field does, and faster while the
    /// user is typing.
    private var caret: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let period: Double = isTyping ? 0.33 : 0.6
            let on = (phase / period).truncatingRemainder(dividingBy: 1) < 0.5

            Rectangle()
                .fill(.white.opacity(0.9))
                .frame(width: 1.5, height: 18)
                .opacity(on ? 1 : 0.15)
        }
    }

    /// The eye that shows the text.
    private var eyeButton: some View {
        Image(systemName: revealsPassword ? "eye.slash" : "eye")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 24, height: 24)
    }

    /// The text as it is shown: as dots, or as it was written.
    private var masked: [Character] {
        if revealsPassword, knowsCharacters {
            return Array(typedPassword)
        }
        // The dots are one per key press, whether or not the app knows which
        // keys they were.
        let count = knowsCharacters ? typedPassword.count : pressedKeys
        return Array(repeating: "\u{2022}", count: count)
    }

    /// Tells where the eye is, in screen coordinates.
    private func reportEye(_ frame: CGRect) {
        // The eye is at the right end of the field.
        let eyeSize: CGFloat = 24
        let x = frame.minX + fieldWidth - 30 + 3
        let y = frame.minY + (fieldHeight - eyeSize) / 2
        onRevealRect?(CGRect(x: x, y: y, width: eyeSize, height: eyeSize))
    }
}
