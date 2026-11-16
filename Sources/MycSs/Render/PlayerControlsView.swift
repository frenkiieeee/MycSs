import SwiftUI

/// The player under the cover: a thin progress bar with the times, and three
/// plain glyphs.
///
/// The look follows Apple Music: no buttons drawn around the icons, the elapsed
/// time on the left and the time remaining on the right. What is ours is the
/// feedback: a press leaves a soft ripple and bounces the icon, and the play
/// glyph glows with the colour of the album.
///
/// None of it is a SwiftUI `Button`. On the lock screen the overlay is
/// click-through, so the clicks never reach the views; the model notices them
/// and checks them against the regions these views report (see
/// `LyricsViewModel.handleClick`). Keeping the same path in the screensaver
/// means there is one behaviour to get right, not two.
struct PlayerControlsView: View {

    @Bindable var model: LyricsViewModel
    let displayID: CGDirectDisplayID
    let width: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ProgressRow(model: model, displayID: displayID)
            HStack(spacing: 0) {
                TransportButton(
                    id: "previous", symbol: "backward.fill", size: 28,
                    model: model, displayID: displayID
                )
                PlayPauseButton(model: model, displayID: displayID)
                TransportButton(
                    id: "next", symbol: "forward.fill", size: 28,
                    model: model, displayID: displayID
                )
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width)
    }
}

// MARK: - Progress

/// The bar and the two times. It is its own view so that only it reads the
/// position, which changes sixty times a second.
private struct ProgressRow: View {

    @Bindable var model: LyricsViewModel
    let displayID: CGDirectDisplayID

    var body: some View {
        let duration = max(model.track.durationSec, 0)
        let position = duration > 0 ? min(max(model.position, 0), duration) : max(model.position, 0)
        let fraction = duration > 0 ? position / duration : 0
        let pressed = model.pressedControl == "seek"

        VStack(spacing: 0) {
            // The region is taller than the bar, so it is easy to hit.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: max(proxy.size.width * fraction, 0))
                }
                // Thin like Apple Music's, and thicker for a moment when it is
                // used.
                .frame(height: pressed ? 9 : 5)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .screenRegion("seek", model: model, display: displayID)

            HStack {
                Text(Self.format(position))
                Spacer()
                // The time remaining, with a minus, as Apple Music shows it.
                Text("-" + Self.format(max(duration - position, 0)))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// `m:ss`, or `h:mm:ss` for the rare track over an hour.
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Buttons

/// Previous and next: one glyph, and a ripple when it is pressed.
private struct TransportButton: View {

    let id: String
    let symbol: String
    let size: CGFloat
    @Bindable var model: LyricsViewModel
    let displayID: CGDirectDisplayID

    var body: some View {
        let pressed = model.pressedControl == id
        ZStack {
            Circle()
                .fill(.white.opacity(pressed ? 0.22 : 0))
                .frame(width: 60, height: 60)
                .scaleEffect(pressed ? 1 : 0.4)
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(pressed ? 0.7 : 0.92))
                .symbolEffect(.bounce, options: .nonRepeating, value: pressed)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: pressed)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .contentShape(Rectangle())
        .screenRegion(id, model: model, display: displayID)
    }
}

/// Play and pause: a bigger glyph that morphs between the two, and glows with
/// the album's colour while the music plays.
private struct PlayPauseButton: View {

    @Bindable var model: LyricsViewModel
    let displayID: CGDirectDisplayID

    var body: some View {
        let pressed = model.pressedControl == "playPause"
        let accent = model.theme.accent.color
        ZStack {
            Circle()
                .fill(.white.opacity(pressed ? 0.22 : 0))
                .frame(width: 84, height: 84)
                .scaleEffect(pressed ? 1 : 0.4)
            Image(systemName: model.isPlayingNow ? "pause.fill" : "play.fill")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                // The glow is only there while the music plays; paused, the
                // glyph is just white.
                .shadow(color: accent.opacity(model.isPlayingNow ? 0.85 : 0), radius: 18)
                .shadow(color: accent.opacity(model.isPlayingNow ? 0.45 : 0), radius: 34)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .nonRepeating, value: pressed)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: pressed)
        .animation(.smooth(duration: 0.4), value: model.isPlayingNow)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .contentShape(Rectangle())
        .screenRegion("playPause", model: model, display: displayID)
    }
}
