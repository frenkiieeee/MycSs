import AppKit
import Foundation

/// Owns the current colour theme and animates it between tracks.
///
/// The theme is derived from the album artwork and interpolated when the track
/// changes, so the screen never cuts from one colour scheme to another.
@MainActor
final class ThemeEngine {

    /// Where the artwork URL comes from.
    private let source: any PlayerSource

    init(source: any PlayerSource) {
        self.source = source
    }

    /// The theme currently in effect.
    private(set) var theme: Theme = .default

    /// How long the cross-fade between two themes lasts, in seconds.
    var transitionDuration: TimeInterval = 1.2

    private var fromTheme: Theme = .default
    private var toTheme: Theme = .default
    private var transitionStart: Date?
    private var artworkTask: Task<Void, Never>?

    /// Called whenever the theme changes, so the view can redraw.
    var onChange: ((Theme) -> Void)?

    /// The artwork of the current track, if it was downloaded.
    private(set) var artwork: NSImage?

    /// Sets the theme for a track, animating from the current one.
    ///
    /// - Parameter theme: the new theme.
    func transition(to theme: Theme) {
        guard theme != self.theme else { return }
        fromTheme = self.theme
        toTheme = theme
        transitionStart = Date()
        Log.line("theme: transitioning \(self.theme.accent.hex) -> \(theme.accent.hex)")
    }

    /// Returns the theme for the current moment, interpolating if a transition
    /// is in progress.
    func currentTheme(at date: Date = Date()) -> Theme {
        guard let transitionStart else { return theme }
        let elapsed = date.timeIntervalSince(transitionStart)
        guard elapsed < transitionDuration else {
            if self.theme != toTheme {
                self.theme = toTheme
                onChange?(toTheme)
            }
            return toTheme
        }

        let amount = elapsed / transitionDuration
        return Theme(
            accent: fromTheme.accent.blended(towards: toTheme.accent, amount: amount),
            secondary: fromTheme.secondary.blended(towards: toTheme.secondary, amount: amount),
            backgroundDeep: fromTheme.backgroundDeep.blended(towards: toTheme.backgroundDeep, amount: amount),
            backgroundMid: fromTheme.backgroundMid.blended(towards: toTheme.backgroundMid, amount: amount)
        )
    }

    /// Downloads the artwork and derives the theme from it.
    ///
    /// - Parameter track: the track whose artwork should be fetched.
    func loadArtwork(for track: NowPlaying) {
        artworkTask?.cancel()
        artwork = nil

        guard track.hasTrack else { return }

        let source = self.source
        let previous = lastArtworkURL
        artworkTask = Task { [weak self] in
            // The player is asked off the main thread (some answer with whole
            // images), and the rest of the search goes to `CoverProvider`.
            let found = await CoverProvider.shared.cover(for: track, previousURL: previous) {
                let url = source.artworkURL()
                return (url, url == nil ? source.artworkData() : nil)
            }
            guard !Task.isCancelled else { return }
            guard let found else {
                Log.line("theme: no cover found for '\(track.title)'")
                return
            }
            Log.line("theme: cover for '\(track.title)' from \(found.origin.rawValue)")
            await MainActor.run {
                self?.lastArtworkURL = found.url
                self?.apply(artwork: found.image)
            }
        }
    }

    /// The artwork URL the player gave last, to notice a stale one.
    private var lastArtworkURL: String?

    private func apply(artwork image: NSImage) {
        artwork = image
        // The artwork drives the theme, but the user can turn that off: in
        // that case the fixed accent colour is used.
        guard AppSettings.shared.useArtworkColours else {
            transition(to: Theme.fixed)
            return
        }
        // The artwork of a monochrome cover falls back to the default.
        if let theme = ArtworkPalette.theme(from: image) {
            transition(to: theme)
        } else {
            transition(to: .default)
        }
    }
}
