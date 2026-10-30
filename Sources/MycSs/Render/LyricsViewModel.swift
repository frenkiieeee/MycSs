import AppKit
import Foundation
import SwiftUI
import Observation

/// Bridges the `SyncEngine` actor to the view layer.
///
/// The engine lives on an actor because it polls the network and Spotify. The
/// view layer needs a plain snapshot it can read on every frame, so this
/// observable object holds the current state and republishes it when it
/// changes.
@MainActor
@Observable
final class LyricsViewModel {

    /// The lyrics for the current track.
    private(set) var lyrics: Lyrics?
    /// The interpolated playback position, in seconds.
    private(set) var position: TimeInterval = 0
    /// The index of the active line.
    private(set) var activeLineIndex: Int?
    /// The track that is playing.
    private(set) var track: NowPlaying = NowPlaying()

    /// The colour theme, derived from the artwork.
    private(set) var theme: Theme = .default
    /// The album artwork, once downloaded.
    private(set) var artwork: NSImage?

    /// The artwork that is being replaced.
    ///
    /// The new cover fades in over the old one, the way the players do it
    /// when the song changes.
    private(set) var previousArtwork: NSImage?

    /// How much of the new artwork is showing, from 0 to 1.
    private(set) var artworkOpacity: Double = 1

    /// How visible the password hint is, from 0 to 1.
    private(set) var hintReveal: Double = 0

    /// Whether the overlay is on screen.
    private(set) var isVisible = false

    /// What the user has written at the lock screen.
    ///
    /// The field of the lock screen belongs to another process and cannot be
    /// read, so the app rebuilds the text from the keys it sees. It is only
    /// used to draw the masked dots of the placeholder.
    private(set) var typedPassword = ""

    /// How many keys the user has pressed.
    ///
    /// The lock screen hides which keys are pressed, but not how many, so on
    /// it the dots are counted instead of being read.
    private(set) var pressedKeys = 0

    /// Whether the app knows the characters that were written.
    ///
    /// It does when the lock screen is not hiding the state of the keyboard.
    private(set) var knowsCharacters = false

    /// Whether the user asked to see what they are writing.
    private(set) var revealsPassword = false

    /// Where the eye button is, in screen coordinates.
    ///
    /// The overlay is click-through, so the click is noticed by the mouse
    /// watcher and checked against this rectangle.
    private(set) var revealRect: CGRect = .zero

    /// Whether the user is typing.
    ///
    /// The overlay covers the lock screen, so the field they are typing in is
    /// hidden. The hint stays on screen while they type, so that they can see
    /// that their keystrokes are going somewhere.
    private(set) var isTyping = false

    /// How far the entrance has come, from 0 to 1.
    ///
    /// It is worked out with the clock and not with an animation: an animation
    /// only moves when the screen is being redrawn, and on the lock screen the
    /// redraws are slow, so the fade would stay at the beginning and the
    /// overlay would not be seen at all.
    private(set) var entranceProgress: Double = 0

    /// When the entrance started.
    private var entranceStartedAt: Date?

    /// How long the entrance lasts.
    private let entranceDuration: TimeInterval = 0.32

    /// Whether the lyrics are still being fetched.
    ///
    /// While this is true the artwork sits in the centre of the screen, so the
    /// screen is never empty, and the lyrics slide in over it when they arrive.
    private(set) var isLoadingLyrics = false

    /// Forces the loading state, for checking the loading layout.
    private var forceLoadingState = false

    private let engine = SyncEngine()
    private let themeEngine = ThemeEngine()
    private let mouseWatcher = MouseWatcher()
    private let keyboardWatcher = KeyboardWatcher()
    private var ticker: Task<Void, Never>?
    private var lastArtworkKey: String = ""

    /// When the pointer last moved.
    private var lastMouseMove: Date = .distantPast
    /// When a key was last pressed.
    private var lastKeyPress: Date = .distantPast
    /// How long after a key press the user still counts as typing.
    private let typingWindow: TimeInterval = 1.6
    /// How long the hint stays visible after the last movement.
    private let hintDuration: TimeInterval = 2.5

    /// Starts the Spotify polling, for the whole life of the app.
    ///
    /// This is separate from `start()` on purpose: the polling runs even when
    /// the Mac is unlocked, so the lyrics of the current track are already on
    /// their way when the screen is locked.
    func startListening() {
        // The demo timeline does not read from Spotify.
        guard !isDemo else { return }
        Task { await engine.start() }
    }

    /// Starts the visual clock and the artwork refresh.
    ///
    /// The Spotify polling runs separately and for as long as the app is
    /// running, so the lyrics of the current track are already on their way
    /// when the screen is locked.
    func start() {
        guard ticker == nil else { return }

        // `--snapshot-loading` simulates the state where the lyrics have not
        // arrived yet, so the loading layout can be checked.
        if CommandLine.arguments.contains("--snapshot-loading") {
            forceLoadingState = true
        }

        // The hint fades in when the pointer moves and fades back out after a
        // moment of stillness.
        mouseWatcher.onMove = { [weak self] _ in
            self?.lastMouseMove = Date()
        }
        mouseWatcher.start()

        // The keyboard is watched for the same reason, and the same way: only
        // the keys that are pressed are read, never anything else.
        keyboardWatcher.onKey = { [weak self] in
            self?.lastKeyPress = Date()
        }
        keyboardWatcher.onText = { [weak self] text in
            self?.typedPassword = text
        }
        keyboardWatcher.start()

        // The click on the eye button. The overlay never gets the clicks
        // itself — it is click-through — so they are noticed here.
        mouseWatcher.onClick = { [weak self] point in
            guard let self, !self.revealRect.isEmpty else { return }
            guard self.revealRect.contains(point) else { return }
            self.revealsPassword.toggle()
        }

        // The visual clock: 60 fps, independent of the poll rate.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // ~60 fps.
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    /// Stops the visual clock. The Spotify polling keeps running so that the
    /// lyrics are ready the moment the screen is locked again.
    func stop() {
        ticker?.cancel()
        ticker = nil
        mouseWatcher.stop()
        keyboardWatcher.stop()
    }

    /// Where the eye button is, so that a click on it can be noticed.
    func setRevealRect(_ rect: CGRect) {
        revealRect = rect
    }

    /// Sets whether the overlay is on screen. It drives the entrance animation.
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            entranceStartedAt = Date()
            entranceProgress = 0
        } else {
            entranceStartedAt = nil
            entranceProgress = 0
        }
        // The lock screen is gone: whatever was written belongs to it.
        if !visible {
            typedPassword = ""
            pressedKeys = 0
            knowsCharacters = false
            revealsPassword = false
            // The hint goes at once, and not faded: the overlay may still be
            // on screen for a moment while the lock screen unlocks.
            hintReveal = 0
        }
    }

    /// Forces the password hint to be fully visible.
    ///
    /// Used by the snapshot tool so the reveal can be checked without moving
    /// the mouse.
    func forceHint() {
        lastMouseMove = Date()
        hintReveal = 1.0
    }

    // MARK: - Demo mode

    /// Whether the app is showing a synthetic timeline instead of Spotify's.
    ///
    /// The demo runs on its own clock, so the movement of the lyrics can be
    /// checked without depending on what is playing or on the network.
    private let isDemo = CommandLine.arguments.contains("--demo")

    /// When the demo timeline started.
    private var demoAnchor: Date?

    /// The lyrics of the demo timeline.
    private var demoLyrics: Lyrics?

    /// A short song with lines of different lengths, so the layout and the
    /// scrolling can be seen.
    private static let demoLRC = """
    [00:00.00] The first line of the demo song
    [00:03.00] A second line that is a little bit longer than the first one
    [00:06.00] Third
    [00:09.00] And this line is quite a lot longer, so that it has to wrap into more than one row of text
    [00:12.00] Short again
    [00:15.00] Another one
    [00:18.00] The last line of the first verse
    [00:21.00] The second verse begins right here
    [00:24.00] With a line that is long enough to wrap around the column of text
    [00:27.00] Almost done
    [00:30.00] The end
    """

    /// Runs the demo timeline: the position advances on its own clock.
    private func refreshDemo() {
        if demoAnchor == nil {
            demoAnchor = Date()
            let lines = WordInterpolator.interpolate(LyricsParser.parseLRC(Self.demoLRC))
            demoLyrics = Lyrics(
                lines: lines,
                duration: 34,
                source: .lrclib,
                wordTimingQuality: .interpolated
            )
            self.track = NowPlaying(
                title: "Demo Song",
                artist: "MycSs",
                album: "Demo",
                durationSec: 34
            )
        }

        let elapsed = Date().timeIntervalSince(demoAnchor!)
        let lyrics = demoLyrics

        if self.lyrics?.lines.count != lyrics?.lines.count {
            self.lyrics = lyrics
        }
        self.position = elapsed
        self.isLoadingLyrics = false

        let index = lyrics?.activeLineIndex(at: elapsed)
        if self.activeLineIndex != index {
            self.activeLineIndex = index
        }

        // The hint fades in with the movement and back out when it stops.
        let sinceMove = Date().timeIntervalSince(lastMouseMove)

        // The hint stays while the user types: the field they are typing in is
        // behind the overlay, and that is exactly the moment they need to see
        // it.
        //
        // It only shows while the screen is locked: the overlay is the lock
        // screen, and on the desktop there is no password to type.
        let target = (isVisible && sinceMove < hintDuration) ? 1.0 : 0.0
        // The hint comes in quickly: it is there to show where the password
        // goes, and a slow fade is felt as a delay when the user starts
        // typing.
        let step = target > hintReveal ? 0.28 : 0.16
        if abs(target - hintReveal) > 0.001 {
            hintReveal += (target - hintReveal) * step
        } else {
            hintReveal = target
        }
    }

    private func refresh() async {
        if isDemo {
            refreshDemo()
            return
        }

        let lyrics = await engine.currentLyrics
        let position = await engine.position
        let activeIndex = await engine.activeLineIndex
        let track = await engine.current
        let isLoading = await engine.isLoadingLyrics

        // Only publish when something actually changed, so SwiftUI does not
        // re-render the whole lyric stack on every frame.
        if self.track.trackKey != track.trackKey {
            // Another song: the lyrics of the previous one do not belong to
            // it, and showing them under the new cover is confusing. They are
            // cleared right away and the new ones take their place when they
            // arrive.
            self.lyrics = nil
            self.activeLineIndex = nil
            self.track = track
        } else if self.lyrics?.lines.count != lyrics?.lines.count
                    || self.activeLineIndex != activeIndex {
            self.lyrics = lyrics
            self.activeLineIndex = activeIndex
        }
        self.position = position
        self.isLoadingLyrics = forceLoadingState || isLoading

        // The entrance, with the clock.
        if let started = entranceStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            let progress = min(max(elapsed / entranceDuration, 0), 1)
            if abs(progress - entranceProgress) > 0.002 {
                entranceProgress = progress
            }
            if progress >= 1 {
                entranceStartedAt = nil
            }
        }

        // The artwork only has to be fetched once per track.
        if track.hasTrack, track.trackKey != lastArtworkKey {
            lastArtworkKey = track.trackKey
            themeEngine.loadArtwork(for: track)
        }

        // The theme is interpolated over time, so it has to be sampled every
        // frame while a transition is running.
        let current = themeEngine.currentTheme()
        if current != self.theme {
            self.theme = current
        }

        // The artwork is published separately: it arrives independently of the
        // theme, and when the artwork has no usable colour the theme does not
        // change at all (it falls back to the default), so tying the artwork to
        // the theme would leave it unpublished forever.
        if themeEngine.artwork !== self.artwork {
            // The old cover stays underneath while the new one fades in over it.
            previousArtwork = self.artwork
            self.artwork = themeEngine.artwork
            artworkOpacity = 0

            // The fade has to start in the update *after* the one that puts
            // the new cover in place, or there would be nothing to fade from.
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.55)) {
                    artworkOpacity = 1
                }
            }
        }

        // The hint fades in with the movement and back out when it stops.
        let sinceMove = Date().timeIntervalSince(lastMouseMove)

        // The hint stays while the user types: the field they are typing in is
        // behind the overlay, and that is exactly the moment they need to see
        // it.
        //
        // It only shows while the screen is locked: the overlay is the lock
        // screen, and on the desktop there is no password to type.
        let target = (isVisible && sinceMove < hintDuration) ? 1.0 : 0.0
        // A smooth fade rather than a jump.
        // The hint comes in quickly: it is there to show where the password
        // goes, and a slow fade is felt as a delay when the user starts
        // typing.
        let step = target > hintReveal ? 0.28 : 0.16
        if abs(target - hintReveal) > 0.001 {
            hintReveal += (target - hintReveal) * step
        } else {
            hintReveal = target
        }
    }
}
