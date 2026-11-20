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

    /// The display this copy of the overlay is on, so the regions it reports can
    /// be turned into screen coordinates.
    var displayID: CGDirectDisplayID = CGMainDisplayID()

    /// Goes up when a setting changes. A settings preview passes it so the view is
    /// drawn again at once: the settings live in `UserDefaults`, which SwiftUI
    /// does not watch.
    var revision = 0

    private var settings: AppSettings { .shared }

    var body: some View {
        let _ = revision
        // The outermost view is a plain rectangle that fills whatever space it is
        // given. Without it, a `GeometryReader` at the root has nothing to
        // measure and the whole view collapses to a few points, the window is on
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
                // With the player under it, the cover also has to leave room for it in
                // the height of the screen.
                let controlsOn = settings.showPlayerControls && model.track.hasTrack
                let coverWidth = min(settings.artworkSize, width * 0.42, height * (controlsOn ? 0.42 : 0.6))
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
                        intensity: settings.animationIntensity,
                        artwork: model.artwork
                    )
                    .frame(width: width, height: height)

                    VStack(spacing: 0) {
                        // The clock goes after a few seconds if the user wants it
                        // to. Its space stays reserved, so the cover does not move:
                        // only the lyrics grow upwards into it.
                        if settings.showClock {
                            clock
                                .padding(.bottom, height * 0.03)
                                .opacity(model.clockHidden ? 0 : 1)
                                .offset(y: model.clockHidden ? -height * 0.02 : 0)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.clockSpace = $0 }
                        }

                        // The cover moves to the middle when the song has no lyrics,
                        // and back to the left if they turn up later.
                        let centered = settings.centerCoverWithoutLyrics
                            && settings.showArtwork
                            && model.lyricsNotFound
                            && !isLoading
                        let lyricsWidth = width - artworkColumn - columnGap - sideMargin * 2

                        ZStack(alignment: .topLeading) {
                            // The lyrics keep their full width even when hidden, so
                            // they are not laid out again while the cover moves.
                            lyricsColumn
                                .frame(width: lyricsWidth)
                                .frame(maxWidth: .infinity, alignment: settings.coverOnRight ? .leading : .trailing)
                                .padding(.top, settings.showClock && model.clockHidden ? -model.clockSpace : 0)
                                .modifier(SongChangeEffect(
                                    kind: settings.songTransition,
                                    reveal: model.lyricsReveal,
                                    leaving: model.lyricsLeaving,
                                    distance: height * 0.05
                                ))
                                // Hidden while the cover is in the middle, and while the
                                // lyrics load and nothing is left to show.
                                .opacity(centered || (isLoading && model.lyrics == nil) ? 0 : 1)
                                .animation(.smooth(duration: 0.4), value: centered)
                                .screenRegion("lyrics", model: model, display: displayID, active: !centered)

                            if settings.showArtwork {
                                artworkColumnView(
                                    isLoading: isLoading,
                                    coverWidth: coverWidth,
                                    columnWidth: centered ? coverWidth : artworkColumn,
                                    controls: controlsOn
                                )
                                .frame(maxWidth: .infinity, alignment: centered ? .center : (settings.coverOnRight ? .trailing : .leading))
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .animation(.smooth(duration: 0.75), value: centered)
                    }
                    .padding(.horizontal, sideMargin)
                    .padding(.top, height * 0.045)
                    .padding(.bottom, height * 0.055)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .animation(.smooth(duration: 0.9), value: model.clockHidden)

                    // A small signature, right in the bottom left corner. It shows
                    // while the user is active and goes when nothing moves.
                    Text("@frenkiieeee")
                        .font(.system(size: max(11, height * 0.0145), weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55 * model.watermarkReveal))
                        .padding(.leading, max(10, width * 0.009))
                        .padding(.bottom, max(8, height * 0.013))
                        .frame(width: width, height: height, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: height)
                .ignoresSafeArea()
                // The entrance: the overlay does not appear all at once.
                .modifier(EntranceModifier(
                    entrance: settings.entranceAnimation,
                    progress: model.entranceProgress
                ))

                // The volume and brightness indicator, which the notch cannot show while the
                // screen is locked. Only on the lock screen (and in the settings preview).
                ZStack {
                    if settings.lockHUD, model.isVisible, model.mode == .lock || model.mode == .preview,
                       let source = model.hudSource, let hud = source.hud {
                        OverlayHUD(hud: hud, shown: source.hudShown, scale: max(1.2, height / 760))
                            .padding(.top, height * 0.035 + 12)
                            .padding(.trailing, width * 0.045)
                            .frame(width: width, height: height, alignment: .topTrailing)
                            .transition(settings.lockHUDAnimation.transition)
                    }
                }
                .animation(settings.lockHUDAnimation.animation, value: model.hudSource?.hud != nil)
                .frame(width: width, height: height)
                .allowsHitTesting(false)

                // The hint sits above everything, in the middle of the screen
                // where the password field is, and along the bottom.
                if model.showsPasswordHint {
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
                    onRevealRect: { rect in model.setRegion("eye", display: displayID, frame: rect) }
                )
                .frame(width: width, height: height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Clock

    private var clock: some View {
        ClockView(model: model)
    }

    // MARK: - Artwork

    /// The artwork column.
    ///
    /// While the lyrics are loading the artwork sits in the centre of the screen;
    /// when they arrive it slides to the left column. The movement is animated,
    /// so it reads as the cover finding its place.
    ///
    /// The title and the artist sit under the artwork, aligned to the artwork's
    /// own left edge, not to the edge of the column, which is wider than the
    /// cover and would leave the text hanging outside it.
    @ViewBuilder
    private func artworkColumnView(
        isLoading: Bool,
        coverWidth: CGFloat,
        columnWidth: CGFloat,
        controls: Bool
    ) -> some View {
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
                // The title and the artist change with their own movement, so a new
                // song does not swap the text in a single frame.
                ZStack(alignment: .topLeading) {
                    trackInfo
                        .id(model.track.trackKey)
                        .transition(settings.songTransition.textTransition)
                }
                // A fixed width, so the text is laid out inside the cover's
                // width and starts at its left edge.
                //
                // The title and the artist are shown as soon as they are
                // known: making them wait for the lyrics left the screen
                // with a cover and nothing else for seconds.
                .frame(width: coverWidth, alignment: .leading)
                .animation(
                    settings.songTransition == .off ? nil : .smooth(duration: max(0.25, settings.songTransitionSeconds * 0.7)),
                    value: model.track.trackKey
                )
            }

            // The player: progress, times and the three buttons.
            if controls {
                PlayerControlsView(model: model, displayID: displayID, width: coverWidth)
                    .padding(.top, 6)
            }
        }
        // What counts as "inside" for a click: outside it, a click closes the
        // overlay.
        .screenRegion("cover", model: model, display: displayID)
        // The column itself hugs the cover, so nothing is centred inside it.
        .frame(width: columnWidth, alignment: settings.coverOnRight ? .trailing : .leading)
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
            let kind = settings.songTransition
            let fade = model.artworkOpacity
            if model.artwork != nil, let previous = model.previousArtwork {
                Image(nsImage: previous)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    // The old one steps back as the new one arrives.
                    .scaleEffect(kind == .cinematic || kind == .glide ? 1 - 0.04 * fade : 1)
                    .blur(radius: kind == .cinematic ? 6 * fade : 0)
            }
            if let current = model.artwork {
                Image(nsImage: current)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    // The new one comes from a little bigger and settles.
                    .scaleEffect(kind == .cinematic || kind == .glide ? 1 + 0.05 * (1 - fade) : 1)
                    .blur(radius: kind == .cinematic ? 8 * (1 - fade) : 0)
                    .opacity(fade)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
        .shadow(color: model.theme.accent.color.opacity(0.3), radius: 40)
        // Like Apple Music: the cover steps back when the music is paused and
        // comes forward when it plays.
        .scaleEffect(model.isPlayingNow || !model.track.hasTrack ? 1 : 0.88)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: model.isPlayingNow)
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
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
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
            Spacer(minLength: 0)
        }
        // Leading alignment, and no `maxWidth: .infinity`: an infinite width
        // would override the width set by the caller and push the text to the
        // middle of the column instead of the cover's left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



// MARK: - Change of song

/// How the lyrics column goes and comes when the song changes: it fades, it
/// also slides (up on the way out, from below on the way in), and in the
/// cinematic style it also loses focus and shrinks a little.
struct SongChangeEffect: ViewModifier {
    var kind: AppSettings.SongTransition
    /// 1 when the column is all there, 0 when it is gone.
    var reveal: Double
    var leaving: Bool
    var distance: CGFloat

    func body(content: Content) -> some View {
        let away = 1 - reveal
        content
            .opacity(kind == .off ? 1 : reveal)
            .offset(y: kind == .glide || kind == .cinematic ? (leaving ? -1 : 1) * away * distance : 0)
            .blur(radius: kind == .cinematic ? away * 10 : 0)
            .scaleEffect(kind == .cinematic ? 1 - away * 0.04 : 1, anchor: .leading)
    }
}

extension AppSettings.SongTransition {
    /// What the title and the artist do when they are replaced.
    var textTransition: AnyTransition {
        switch self {
        case .off:
            return .identity
        case .fade:
            return .opacity
        case .glide:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 14)),
                removal: .opacity.combined(with: .offset(y: -10))
            )
        case .cinematic:
            return .asymmetric(
                insertion: AnyTransition(.blurReplace).combined(with: .offset(y: 14)),
                removal: AnyTransition(.blurReplace).combined(with: .offset(y: -10))
            )
        }
    }
}


/// The volume or brightness indicator on the lock screen: a dark pill with the icon and
/// the value, drawn like the notch's own (same style, numbers and motion), only bigger.
struct OverlayHUD: View {
    let hud: NotchHUD
    let shown: CGFloat
    var scale: CGFloat = 1.2

    var body: some View {
        HStack(spacing: 10) {
            HUDIcon(hud: hud, shown: shown, size: 15)
            HUDValue(hud: hud, shown: shown, barWidth: 110)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Capsule().fill(.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .scaleEffect(scale, anchor: .topTrailing)
    }
}
