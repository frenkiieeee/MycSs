import AppKit
import Foundation
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

    /// How visible the password hint is, from 0 to 1.
    private(set) var hintReveal: Double = 0

    private let engine = SyncEngine()
    private let themeEngine = ThemeEngine()
    private let mouseWatcher = MouseWatcher()
    private var ticker: Task<Void, Never>?
    private var lastArtworkKey: String = ""

    /// When the pointer last moved.
    private var lastMouseMove: Date = .distantPast
    /// How long the hint stays visible after the last movement.
    private let hintDuration: TimeInterval = 2.5

    func start() {
        guard ticker == nil else { return }
        Task { await engine.start() }

        // The hint fades in when the pointer moves and fades back out after a
        // moment of stillness.
        mouseWatcher.onMove = { [weak self] _ in
            self?.lastMouseMove = Date()
        }
        mouseWatcher.start()

        // The visual clock: 60 fps, independent of the poll rate.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // ~60 fps.
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        mouseWatcher.stop()
        Task { await engine.stop() }
    }

    /// Forces the password hint to be fully visible.
    ///
    /// Used by the snapshot tool so the reveal can be checked without moving
    /// the mouse.
    func forceHint() {
        lastMouseMove = Date()
        hintReveal = 1.0
    }

    private func refresh() async {
        let lyrics = await engine.currentLyrics
        let position = await engine.position
        let activeIndex = await engine.activeLineIndex
        let track = await engine.current

        // Only publish when something actually changed, so SwiftUI does not
        // re-render the whole lyric stack on every frame.
        if self.lyrics?.lines.count != lyrics?.lines.count
            || self.activeLineIndex != activeIndex
            || self.track.trackKey != track.trackKey {
            self.lyrics = lyrics
            self.activeLineIndex = activeIndex
            self.track = track
        }
        self.position = position

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
            self.artwork = themeEngine.artwork
        }

        // The hint fades in with the movement and back out when it stops.
        let sinceMove = Date().timeIntervalSince(lastMouseMove)
        let target = sinceMove < hintDuration ? 1.0 : 0.0
        // A smooth fade rather than a jump.
        let step = target > hintReveal ? 0.08 : 0.04
        if abs(target - hintReveal) > 0.001 {
            hintReveal += (target - hintReveal) * step
        } else {
            hintReveal = target
        }
    }
}
