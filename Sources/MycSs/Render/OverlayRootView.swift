import SwiftUI

/// The screen shown on the lock screen.
///
/// The layout follows the reference screenshots: the clock at the top, the album
/// artwork on the left, and the lyrics in a column on the right, over an
/// animated background built from the artwork's colours.
///
/// The layout is driven by fractions of the available width rather than fixed
/// points, so it scales from a small laptop screen to a large display.
struct OverlayRootView: View {

    /// The model is owned by the overlay controller and shared by every panel.
    let model: LyricsViewModel

    private var settings: AppSettings { .shared }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            // The artwork column takes a fixed fraction of the width, and the
            // lyrics get the rest. Both are centred in their column, so the
            // artwork never touches the screen edge and the lyrics never run
            // underneath it.
            let artworkColumn = width * 0.34
            let sideMargin = width * 0.055

            ZStack {
                BackgroundView(
                    theme: model.theme,
                    mode: settings.backgroundMode,
                    intensity: settings.animationIntensity
                )

                VStack(spacing: 0) {
                    if settings.showClock {
                        clock
                            .padding(.bottom, height * 0.03)
                    }

                    HStack(alignment: .center, spacing: 0) {
                        // The artwork, centred in its own column.
                        if settings.showArtwork {
                            artwork
                                .frame(width: artworkColumn - sideMargin * 2, height: artworkColumn - sideMargin * 2)
                                .frame(width: artworkColumn)
                        }

                        lyricsColumn
                            .frame(width: width - artworkColumn - sideMargin * 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .padding(.horizontal, sideMargin)
                .padding(.top, height * 0.045)
                .padding(.bottom, height * 0.055)
                .frame(maxHeight: .infinity, alignment: .center)
                // When the hint is showing, the lyrics step back so the
                // password area is the thing the eye goes to.
                .opacity(1.0 - model.hintReveal * 0.45)
                .animation(.easeOut(duration: 0.25), value: model.hintReveal)
            }
            .ignoresSafeArea()

            // The hint sits above everything, in the middle of the screen where
            // the password field is, and along the bottom.
            PasswordHintView(
                reveal: model.hintReveal,
                accent: model.theme.accent.color
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The artwork's side length.
    ///
    /// It follows the width of its column so it never overflows, and it is
    /// capped so it does not become absurd on a very wide display.
    private func artworkSize(for width: CGFloat, height: CGFloat) -> CGFloat {
        let base = min(width, height)
        let fraction = settings.artworkSize / 340.0
        return min(base * 0.40 * fraction, settings.artworkSize)
    }

    // MARK: - Clock

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 74, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: model.theme.accent.color.opacity(0.35), radius: 30)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        if let artwork = model.artwork {
            // A square that fits inside its column and stays centred.
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
                .shadow(color: model.theme.accent.color.opacity(0.3), radius: 40)
        }
    }

    // MARK: - Lyrics

    private var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.showTrackInfo {
                trackInfo
                    .padding(.bottom, 18)
            }

            LyricsView(
                lyrics: model.lyrics,
                position: model.position,
                activeIndex: model.activeLineIndex,
                activeColor: model.theme.accent.color,
                inactiveColor: .white.opacity(0.3),
                effect: settings.lyricEffect,
                font: Font(settings.lyricsFont)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.track.title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
            Text(model.track.artist)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}
