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

    // MARK: - Song change

    /// How much of the lyrics column is showing, from 0 to 1. It goes to 0 when the
    /// song changes and back to 1 when the new lyrics are in.
    private(set) var lyricsReveal: Double = 1
    /// Whether the column is on its way out (it goes up) or on its way in (it comes from below).
    private(set) var lyricsLeaving = false
    /// True while the old lyrics are leaving: the new ones wait for them.
    @ObservationIgnored private var lyricsSwapping = false
    @ObservationIgnored private var swapTask: Task<Void, Never>?

    /// Pictures from the self tests are taken synchronously: nothing waits there.
    private var animatesSongChange: Bool {
        AppSettings.shared.songTransition != .off
            && !SettingsPreviewSnapshot.isRunning && !NotchSnapshot.isActive
    }

    /// How visible the password hint is, from 0 to 1.
    private(set) var hintReveal: Double = 0

    /// Whether the overlay is on screen.
    private(set) var isVisible = false

    /// Whether the password hint can be drawn: only on the lock screen.
    private(set) var showsPasswordHint = true

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

    /// Whether the user is typing.
    ///
    /// The overlay covers the lock screen, so the field they are typing in is
    /// hidden. The hint stays on screen while they type, so that they can see
    /// that their keystrokes are going somewhere.
    private(set) var isTyping = false

    /// Whether the clock has gone: a few seconds after the lyrics appeared, if the
    /// user asked for that. The view takes it off the screen and the rest moves up.
    private(set) var clockHidden = false

    /// The height the clock takes at the top, gap under it included. When the clock
    /// goes, the cover stays where it was and only the lyrics grow into this space.
    var clockSpace: CGFloat = 0

    /// How visible the signature in the corner is, from 0 to 1. It shows when the
    /// overlay appears and while the user is active, and fades when nothing moves.
    private(set) var watermarkReveal: Double = 0

    /// When the overlay last appeared.
    @ObservationIgnored private var appearedAt = Date()

    /// How long the signature stays after the overlay appears or the last movement.
    private let watermarkHold: TimeInterval = 3.5

    /// When the clock was last shown in full. It starts when the overlay appears.
    @ObservationIgnored private var clockShownAt = Date()

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

    /// Whether every source answered and none had lyrics for this track.
    private(set) var lyricsNotFound = false

    /// Whether the player is playing right now, for the play/pause icon.
    private(set) var isPlayingNow = false

    private(set) var mode: OverlayMode = .lock
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private let escapeWatcher = EscapeWatcher()

    private let engine: SyncEngine
    private let themeEngine: ThemeEngine
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

    /// - Parameter demo: a synthetic song on its own clock instead of the real
    ///   player. The settings previews use it, so they never touch the music.
    init(demo: Bool = DemoFlags.isDemo) {
        isDemo = demo
        // One hub shared by the engine and the theme, so both follow the same
        // player.
        let hub = PlayerHub()
        engine = SyncEngine(source: hub)
        themeEngine = ThemeEngine(source: hub)
    }

    /// Whether a player is playing right now, for the idle trigger.
    func isMusicPlaying() async -> Bool {
        await engine.isPlaying
    }

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
    ///
    /// - Parameter watchInput: whether the mouse and the keyboard are watched.
    ///   That is only for the lock screen, where the password hint needs it.
    ///   The screensaver never looks at the keyboard.
    func start(mode: OverlayMode = .lock) {
        guard !overlayRunning else { return }
        overlayRunning = true
        self.mode = mode
        showsPasswordHint = mode != .presentation
        startedAt = Date()

        // `--snapshot-loading` simulates the state where the lyrics have not
        // arrived yet, so the loading layout can be checked.
        if DemoFlags.loading {
            forceLoadingState = true
        }

        // The overlay never gets the clicks itself on the lock screen (it is
        // click-through, so that the password field can be used), so every click
        // is noticed here and checked against the regions the views report.
        mouseWatcher.onClick = { [weak self] point in
            self?.handleClick(point)
        }
        // The hint fades in when the pointer moves and fades back out after a
        // moment of stillness.
        mouseWatcher.onMove = { [weak self] _ in
            self?.lastMouseMove = Date()
        }
        mouseWatcher.start()

        switch mode {
        case .lock, .preview:
            // The keyboard is watched for the password hint: only the keys that
            // are pressed are read, never anything else.
            keyboardWatcher.onKey = { [weak self] in
                self?.lastKeyPress = Date()
            }
            keyboardWatcher.onText = { [weak self] text in
                self?.typedPassword = text
            }
            keyboardWatcher.onEscape = { [weak self] in
                self?.requestDismiss()
            }
            keyboardWatcher.start()

        case .presentation:
            // The screensaver has no password to type, so it only listens for
            // Escape and never reads any other key.
            escapeWatcher.onEscape = { [weak self] in
                self?.requestDismiss()
            }
            escapeWatcher.start()
        }

        ensureTicker()
    }

    // MARK: - Settings preview

    /// Whether this model only feeds a preview in the settings window: the demo
    /// song loops, nothing is watched and no password hint is drawn.
    @ObservationIgnored private(set) var isSettingsPreview = false

    /// Whether the preview plays the clock going away and coming back.
    @ObservationIgnored var previewClockCycle = false

    /// The preview can pretend the song has no lyrics, or that it is paused.
    var previewWithoutLyrics = false
    var previewPaused = false

    /// Starts the model as a live preview inside the settings window.
    func startPreview() {
        guard !overlayRunning else { return }
        isSettingsPreview = true
        overlayRunning = true
        mode = .preview
        showsPasswordHint = false
        setVisible(true)
        ensureTicker()
    }

    /// Stops the preview, so a closed settings page costs nothing.
    func stopPreview() {
        guard isSettingsPreview else { return }
        isSettingsPreview = false
        overlayRunning = false
        setVisible(false)
        if !notchActive {
            ticker?.cancel()
            ticker = nil
        }
    }

    /// Plays the entrance again, to judge the animation that is chosen.
    func replayEntrance() {
        guard isVisible else { return }
        entranceStartedAt = Date()
        entranceProgress = 0
        clockShownAt = Date()
    }

    /// Whether the overlay (lock screen or screensaver) is using the model.
    @ObservationIgnored private var overlayRunning = false

    /// The notch's model, which holds the volume and brightness indicator. It is set
    /// **only while the screen is locked**: the notch is hidden then and the overlay
    /// draws the indicator instead. Unlocked it is nil, so the overlay never draws it.
    /// (It is observable on purpose: the view has to notice when it is set.)
    var hudSource: NotchModel?

    /// Whether the notch is using the model.
    @ObservationIgnored private(set) var notchActive = false
    /// Whether the notch is open, which asks for a faster refresh.
    @ObservationIgnored var notchExpanded = false

    /// Turns the notch's use of the model on or off. The visual clock keeps
    /// running while either of them needs it.
    func setNotchActive(_ active: Bool) {
        notchActive = active
        if active {
            ensureTicker()
        } else if !overlayRunning {
            ticker?.cancel()
            ticker = nil
        }
    }

    /// The visual clock. Sixty times a second while the overlay is on screen;
    /// slower for the notch, which only has to show a progress bar: thirty times
    /// a second when it is open, ten when it is closed.
    private func ensureTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: UInt64 = await MainActor.run { [weak self] in
                    guard let self else { return 100_000_000 }
                    // A preview is a small picture: twenty-five frames are plenty.
                    if self.isSettingsPreview { return 40_000_000 }
                    if self.isVisible { return 16_666_667 }
                    return self.notchExpanded ? 33_000_000 : 100_000_000
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    /// Stops the visual clock. The Spotify polling keeps running so that the
    /// lyrics are ready the moment the screen is locked again.
    func stop() {
        overlayRunning = false
        // The notch may still need the clock.
        if !notchActive {
            ticker?.cancel()
            ticker = nil
        }
        mouseWatcher.stop()
        keyboardWatcher.stop()
        escapeWatcher.stop()
        // The regions of the overlay go; the notch's stay.
        regions = regions.filter { $0.key.hasPrefix("notch.") }
    }

    // MARK: - Clicks and leaving

    /// How the overlay is being used.
    enum OverlayMode {
        /// On the lock screen: click-through, with the password hint.
        case lock
        /// Over the desktop, as a screensaver: no password hint.
        case presentation
        /// The development preview.
        case preview
    }

    /// Asked to close the overlay: Escape, or a click outside the lyrics. The
    /// overlay controller decides what closing means in the current mode.
    @ObservationIgnored var onDismissRequest: (() -> Void)?

    /// How long after showing the overlay a click or Escape is ignored, so the
    /// gesture that opened it does not close it again.
    private let dismissGrace: TimeInterval = 0.8

    /// Where each clickable thing is, in screen coordinates (bottom left origin,
    /// the same as the pointer). The key is `"<id>#<display>"`.
    @ObservationIgnored private var regions: [String: CGRect] = [:]

    /// Reports where something is on screen.
    ///
    /// - Parameter frame: the frame in the coordinates of the overlay's window
    ///   (SwiftUI's `.global`, origin at the top left).
    func setRegion(_ id: String, display: CGDirectDisplayID, frame: CGRect) {
        let screen = NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main
        guard let screen else { return }
        // From the window's coordinates (top left) to the screen's (bottom left).
        regions["\(id)#\(display)"] = CGRect(
            x: screen.frame.minX + frame.minX,
            y: screen.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func region(_ id: String, containing point: CGPoint) -> CGRect? {
        for (key, rect) in regions where key.hasPrefix(id + "#") && rect.contains(point) {
            return rect
        }
        return nil
    }

    private func handleClick(_ point: CGPoint) {
        guard Date().timeIntervalSince(startedAt) > dismissGrace else { return }

        // The eye of the password hint, only while the hint is on screen.
        if hintReveal > 0.3, region("eye", containing: point) != nil {
            revealsPassword.toggle()
            return
        }

        // The player controls, most specific first.
        if showsControls {
            if region("previous", containing: point) != nil { press("previous", .previous); return }
            if region("playPause", containing: point) != nil { press("playPause", .playPause); return }
            if region("next", containing: point) != nil { press("next", .next); return }
            if let bar = region("seek", containing: point), bar.width > 0, track.durationSec > 0 {
                let fraction = min(max((point.x - bar.minX) / bar.width, 0), 1)
                perform(.seek(fraction * track.durationSec))
                return
            }
        }

        // On the lyrics or on the cover: nothing to do.
        if region("cover", containing: point) != nil || region("lyrics", containing: point) != nil {
            return
        }

        // Anywhere else closes the overlay.
        requestDismiss()
    }

    private func requestDismiss() {
        guard AppSettings.shared.dismissOnEscapeOrClick else { return }
        guard Date().timeIntervalSince(startedAt) > dismissGrace else { return }
        onDismissRequest?()
    }

    // MARK: - Player controls

    /// Whether the controls are on screen, so their regions count as clickable.
    private var showsControls: Bool {
        AppSettings.shared.showPlayerControls && track.hasTrack
    }

    /// The control that was just pressed, for a moment, to draw it pressed.
    private(set) var pressedControl: String?

    /// How many times each control has been pressed; the icons animate on it.
    private(set) var pressCount = 0

    /// The last command a control sent, for the self test.
    @ObservationIgnored private(set) var lastCommand: PlayerCommand?

    func perform(_ command: PlayerCommand) {
        lastCommand = command
        // The demo never touches the real player: it would pause what the user
        // is listening to. It only changes its own picture.
        if isDemo {
            Log.line("demo: command \(command)")
            if command == .playPause { demoPaused.toggle() }
            return
        }
        Task { await engine.perform(command) }
    }

    /// Whether the demo timeline was paused with the play button.
    @ObservationIgnored private var demoPaused = DemoFlags.paused

    private func press(_ id: String, _ command: PlayerCommand) {
        pressedControl = id
        pressCount += 1
        perform(command)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            if pressedControl == id { pressedControl = nil }
        }
    }

    /// Sets whether the overlay is on screen. It drives the entrance animation.
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        appearedAt = Date()
        clockShownAt = Date()
        if clockHidden { clockHidden = false }
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
    private let isDemo: Bool

    /// When the demo timeline started.
    private var demoAnchor: Date?

    /// The lyrics of the demo timeline.
    private var demoLyrics: Lyrics?

    /// The two songs of the demo, to see the change from one to the other.
    @ObservationIgnored private var demoSongIndex = 0
    /// What the column was last given in the demo: which song, or none.
    @ObservationIgnored private var demoShownKey: String?

    private static func makeDemoLyrics(_ index: Int) -> Lyrics {
        let lines = WordInterpolator.interpolate(LyricsParser.parseLRC(index == 0 ? DemoContent.lrc : DemoContent.lrc2))
        return Lyrics(lines: lines, duration: 34, source: .lrclib, wordTimingQuality: .interpolated)
    }

    private func demoTrack(_ index: Int) -> NowPlaying {
        index == 0
            ? NowPlaying(title: "Demo Song", artist: "MycSs", album: "Demo", durationSec: 34)
            : NowPlaying(title: "Another Song", artist: "Frenkiieeee", album: "Demo 2", durationSec: 34)
    }

    /// Plays the other demo song, to judge the change of song in a preview.
    func previewNextSong() {
        guard isDemo, demoAnchor != nil else { return }
        demoSongIndex = (demoSongIndex + 1) % 2
        demoAnchor = Date()
        demoLyrics = Self.makeDemoLyrics(demoSongIndex)
        let cover = DemoContent.cover(variant: demoSongIndex)
        swapArtwork(to: cover)
        if let derived = ArtworkPalette.theme(from: cover) { theme = derived }
        track = demoTrack(demoSongIndex)
    }

    /// Runs the demo timeline: the position advances on its own clock.
    private func refreshDemo() {
        if demoAnchor == nil {
            demoAnchor = Date()
            demoLyrics = Self.makeDemoLyrics(0)
            self.track = demoTrack(0)
        }

        var elapsed = Date().timeIntervalSince(demoAnchor!)
        // A preview has no end: the demo song starts over.
        if isSettingsPreview { elapsed = elapsed.truncatingRemainder(dividingBy: 34) }
        // `--demo-nolyrics` pretends no source had the lyrics, to check how the
        // cover moves to the middle.
        let lyrics = (DemoFlags.noLyrics || previewWithoutLyrics) ? nil : demoLyrics
        let notFound = lyrics == nil
        if lyricsNotFound != notFound { lyricsNotFound = notFound }
        // A cover, so the layout can be judged. `--demo-mascot` uses the mascot;
        // otherwise a coloured square, which looks like an album and gives the
        // theme real colours to work with.
        if artwork == nil {
            let image: NSImage? = DemoFlags.mascot
                ? NSImage(contentsOfFile: "Assets/Mascot/png/mycss-feliz-512.png")
                : DemoContent.cover()
            if let image {
                artwork = image
                if let derived = ArtworkPalette.theme(from: image) { theme = derived }
            }
        }

        // What the column should hold: one of the songs, or nothing. When it is not what
        // it holds, the old one leaves first.
        let wantedKey = lyrics == nil ? "none" : "song\(demoSongIndex)"
        if wantedKey != demoShownKey {
            if self.lyrics != nil, !lyricsSwapping { beginLyricsSwap() }
            if self.lyrics == nil, !lyricsSwapping {
                self.lyrics = lyrics
                demoShownKey = wantedKey
            }
        }
        revealLyricsIfReady()
        self.position = elapsed
        self.isLoadingLyrics = false
        updateEntrance()
        // The demo plays until its play button is pressed (or `--demo-paused`).
        let playing = !demoPaused && !previewPaused
        if isPlayingNow != playing { isPlayingNow = playing }

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
        let target = (isVisible && showsPasswordHint && sinceMove < hintDuration) ? 1.0 : 0.0
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


    /// Moves the entrance forward with the clock.
    ///
    /// It has to run in the demo timeline too: it used to be skipped there, the
    /// entrance never left 0, and the whole overlay stayed invisible.
    private func updateEntrance() {
        guard let started = entranceStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        let progress = min(max(elapsed / entranceDuration, 0), 1)
        if abs(progress - entranceProgress) > 0.002 {
            entranceProgress = progress
        }
        if progress >= 1 {
            entranceStartedAt = nil
        }
    }

    /// Decides whether the clock is on screen: it goes after the time the user chose
    /// and, if they want it, comes back for a moment when the mouse moves.
    private func updateClock() {
        let settings = AppSettings.shared
        var hidden = false
        if isVisible, settings.showClock, settings.clockAutoHide {
            let seconds = settings.clockAutoHideSeconds
            let shownFor = Date().timeIntervalSince(clockShownAt)
            if isSettingsPreview {
                // The preview shows the clock coming and going, over and over, but
                // only on the page where that is being set up.
                if previewClockCycle {
                    hidden = shownFor >= seconds
                    if shownFor >= seconds + 2.5 { clockShownAt = Date(); hidden = false }
                }
            } else {
                hidden = shownFor >= seconds
                if hidden, settings.clockRevealOnMove,
                   Date().timeIntervalSince(lastMouseMove) < 1.5 {
                    hidden = false
                }
            }
        }
        if hidden != clockHidden {
            clockHidden = hidden
            if !isSettingsPreview { Log.line("clock: \(hidden ? "hidden" : "shown") after \(Int(Date().timeIntervalSince(clockShownAt))) s") }
        }
    }

    /// Fades the signature in while the user is active and out when they are not.
    private func updateWatermark() {
        let now = Date()
        let active = isVisible && (
            isSettingsPreview
            || now.timeIntervalSince(appearedAt) < watermarkHold
            || now.timeIntervalSince(lastMouseMove) < watermarkHold
            || now.timeIntervalSince(lastKeyPress) < watermarkHold
        )
        let target = active ? 1.0 : 0.0
        guard abs(target - watermarkReveal) > 0.002 else {
            if watermarkReveal != target { watermarkReveal = target }
            return
        }
        // Quickly in, slowly out, so it does not flicker.
        watermarkReveal += (target - watermarkReveal) * (target > watermarkReveal ? 0.2 : 0.06)
    }

    // MARK: - Song change

    /// The lyrics on screen stop belonging to the song: they leave, and the column
    /// waits empty for the new ones.
    private func beginLyricsSwap() {
        swapTask?.cancel()
        let settings = AppSettings.shared
        guard animatesSongChange, lyrics != nil else {
            // Nothing to take away, or no animation: the column is ready for the next ones.
            lyricsSwapping = false
            lyricsLeaving = false
            lyrics = nil
            activeLineIndex = nil
            lyricsReveal = animatesSongChange ? 0 : 1
            return
        }
        let seconds = settings.songTransitionSeconds
        let exit = max(0.12, seconds * 0.45)
        lyricsSwapping = true
        lyricsLeaving = true
        withAnimation(.easeIn(duration: exit)) { lyricsReveal = 0 }
        swapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(exit * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Invisible by now: the direction can change without anyone seeing it.
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                lyrics = nil
                activeLineIndex = nil
                lyricsLeaving = false
            }
            lyricsSwapping = false
        }
    }

    /// Brings the column in once there are lyrics to show.
    private func revealLyricsIfReady() {
        guard lyrics != nil, !lyricsSwapping, lyricsReveal < 1 else { return }
        if animatesSongChange {
            withAnimation(.smooth(duration: AppSettings.shared.songTransitionSeconds)) { lyricsReveal = 1 }
        } else {
            lyricsReveal = 1
        }
    }

    /// Replaces the cover with a new one, fading it in over the old one.
    private func swapArtwork(to image: NSImage?) {
        previousArtwork = artwork
        artwork = image
        artworkOpacity = 0
        let seconds = animatesSongChange ? max(0.25, AppSettings.shared.songTransitionSeconds * 0.8) : 0.01
        Task { @MainActor in
            withAnimation(.easeInOut(duration: seconds)) { artworkOpacity = 1 }
        }
    }

    private func refresh() async {
        updateClock()
        updateWatermark()
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
            // Another song: the lyrics of the previous one do not belong to it. They
            // leave on their own (or at once, with the animation off) and the new
            // ones come in when they arrive.
            self.track = track
            beginLyricsSwap()
        } else if !lyricsSwapping, self.lyrics?.lines.count != lyrics?.lines.count
                    || self.lyrics?.source != lyrics?.source
                    || self.lyrics?.wordTimingQuality != lyrics?.wordTimingQuality
                    || self.activeLineIndex != activeIndex {
            self.lyrics = lyrics
            self.activeLineIndex = activeIndex
        }
        revealLyricsIfReady()
        self.position = position
        self.isLoadingLyrics = forceLoadingState || isLoading
        let notFound = await engine.lyricsNotFound && track.hasTrack
        if self.lyricsNotFound != notFound { self.lyricsNotFound = notFound }
        let playing = await engine.isPlaying
        if self.isPlayingNow != playing { self.isPlayingNow = playing }

        updateEntrance()

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
            let seconds = animatesSongChange ? max(0.25, AppSettings.shared.songTransitionSeconds * 0.8) : 0.01
            Task { @MainActor in
                withAnimation(.easeInOut(duration: seconds)) {
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
        let target = (isVisible && showsPasswordHint && sinceMove < hintDuration) ? 1.0 : 0.0
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
