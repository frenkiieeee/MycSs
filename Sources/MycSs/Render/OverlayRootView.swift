import SwiftUI

/// The screen shown on the lock screen.
///
/// The layout follows the reference screenshots: the clock at the top, the album
/// artwork on the left with the title and artist under it, and the lyrics in a
/// column on the right, over an animated background built from the artwork's
/// colours.
///
/// **While the lyrics are loading** the artwork sits in the centre of the screen,
/// and when the lyrics arrive it slides over to the left. That way the screen is
/// never empty, and the change of layout reads as the cover moving into place.
struct OverlayRootView: View {

    /// The model is owned by the overlay controller and shared by every panel.
    ///
    /// It is `@Bindable` rather than a plain `let` so that SwiftUI observes it:
    /// with a plain `let`, the view is never invalidated when the lyrics arrive,
    /// and the overlay keeps showing an empty screen.
    @Bindable var model: LyricsViewModel

    private var settings: AppSettings { .shared }

    var body: some View {
        // The outermost view is a plain rectangle that fills whatever space it is
        // given. Without it, a `GeometryReader` at the root has nothing to
        // measure and the whole view collapses to a few points — the window is on
        // screen but nothing is drawn in it.
        ZStack {
            Color.clear

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                // The cover takes the size the settings ask for, but it never
                // grows past its share of the screen. The lyrics get the rest.
                // The cover is not flush against the edge of the screen, and the
                // lyrics start further to the right, so neither of them crowds
                // the other.
                let sideMargin = width * 0.075
                let coverWidth = min(settings.artworkSize, width * 0.42)
                // The column is the cover plus the margin that keeps it away
                // from the edge of the screen.
                let artworkColumn = coverWidth + sideMargin * 0.9
                // The gap between the cover and the lyrics.
                let columnGap = width * 0.03
                // While the lyrics load, the artwork takes the whole screen.
                let isLoading = model.isLoadingLyrics

                ZStack {
                    // The background fills the screen.
                    BackgroundView(
                        theme: model.theme,
                        mode: settings.backgroundMode,
                        intensity: settings.animationIntensity
                    )
                    .frame(width: width, height: height)

                    VStack(spacing: 0) {
                        if settings.showClock {
                            clock
                                .padding(.bottom, height * 0.03)
                        }

                        HStack(alignment: .center, spacing: columnGap) {
                            if settings.showArtwork {
                                artworkColumnView(
                                    isLoading: isLoading,
                                    coverWidth: coverWidth,
                                    columnWidth: artworkColumn
                                )
                            }

                            lyricsColumn
                                .frame(width: width - artworkColumn - columnGap - sideMargin * 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(isLoading ? 0 : 1)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, sideMargin)
                    .padding(.top, height * 0.045)
                    .padding(.bottom, height * 0.055)
                    .frame(width: width, height: height, alignment: .topLeading)
                }
                .frame(width: width, height: height)
                .ignoresSafeArea()
                // The entrance: the overlay does not appear all at once.
                .modifier(EntranceModifier(
                    entrance: settings.entranceAnimation,
                    progress: model.entranceProgress
                ))

                // The hint sits above everything, in the middle of the screen
                // where the password field is, and along the bottom.
                PasswordHintView(
                    reveal: model.hintReveal,
                    isTyping: model.isTyping,
                    typedPassword: model.typedPassword,
                    pressedKeys: model.pressedKeys,
                    knowsCharacters: model.knowsCharacters,
                    revealsPassword: model.revealsPassword,
                    accent: model.theme.accent.color,
                    // The same margin as the cover and the title, so the
                    // password hint is in line with them.
                    sideMargin: sideMargin,
                    onRevealRect: { rect in model.setRevealRect(rect) }
                )
                .frame(width: width, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Clock

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 104, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: model.theme.accent.color.opacity(0.35), radius: 34)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Artwork

    /// The artwork column.
    ///
    /// While the lyrics are loading the artwork sits in the centre of the screen;
    /// when they arrive it slides to the left column. The movement is animated,
    /// so it reads as the cover finding its place.
    ///
    /// The title and the artist sit under the artwork, aligned to the artwork's
    /// own left edge — not to the edge of the column, which is wider than the
    /// cover and would leave the text hanging outside it.
    @ViewBuilder
    private func artworkColumnView(isLoading: Bool, coverWidth: CGFloat, columnWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
                .frame(width: coverWidth, height: coverWidth)
            // The cover is pinned to the left edge of the column, and the whole
            // column is pinned to the left of the screen, so the title below it
            // starts at exactly the same x as the cover's left edge.
            //
            // The cover does not move while the lyrics are loading: it used to
            // travel across the screen and back, and that was the most
            // disorienting part of a song change.
            .frame(width: coverWidth, alignment: .leading)

            if settings.showTrackInfo {
                trackInfo
                    // A fixed width, so the text is laid out inside the cover's
                    // width and starts at its left edge.
                    //
                    // The title and the artist are shown as soon as they are
                    // known: making them wait for the lyrics left the screen
                    // with a cover and nothing else for seconds.
                    .frame(width: coverWidth, alignment: .leading)
            }
        }
        // The column itself hugs the cover, so nothing is centred inside it.
        .frame(width: columnWidth, alignment: .leading)
        .animation(.smooth(duration: 0.55), value: isLoading)
    }

    /// The cover.
    ///
    /// When the song changes, the new cover fades in over the old one instead
    /// of replacing it: a cut looks like a glitch, a fade looks like the
    /// player moving on to the next song.
    private var artwork: some View {
        ZStack {
            // The old cover is only drawn while the new one is fading in.
            if model.artwork != nil, let previous = model.previousArtwork {
                Image(nsImage: previous)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            }
            if let current = model.artwork {
                Image(nsImage: current)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(model.artworkOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
        .shadow(color: model.theme.accent.color.opacity(0.3), radius: 40)
    }

    // MARK: - Lyrics

    private var lyricsColumn: some View {
        LyricsView(
            lyrics: model.lyrics,
            activeIndex: model.activeLineIndex,
            model: model,
            inactiveColor: .white.opacity(0.3),
            effect: settings.lyricEffect,
            font: Font(settings.lyricsFont)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The title and the artist, under the artwork.
    ///
    /// Their size follows the size of the lyrics, so the whole screen scales
    /// together when the text is made bigger.
    private var trackInfo: some View {
        let scale = settings.fontSize / 42
        return VStack(alignment: .leading, spacing: 3) {
            Text(model.track.title)
                .font(.system(size: 24 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.track.artist)
                .font(.system(size: 19 * scale, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
        }
        // Leading alignment, and no `maxWidth: .infinity`: an infinite width
        // would override the width set by the caller and push the text to the
        // middle of the column instead of the cover's left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

