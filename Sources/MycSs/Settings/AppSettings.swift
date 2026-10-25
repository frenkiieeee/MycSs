import AppKit
import Foundation
import Observation

/// The user's settings.
///
/// Stored in `UserDefaults` under the app's own domain. Every value has a
/// sensible default, so a fresh install works without any configuration.
///
/// This is a class rather than a struct because it is a singleton whose
/// properties are mutated from the menu; with a struct, `shared` would be a
/// `let` and its properties could not be written to.
///
/// It is `@Observable` so that the settings panel and the overlay both react
/// to a change the moment it is made.
@Observable
final class AppSettings {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let displayMode = "displayMode"
        static let sleepAfterMinutes = "sleepAfterMinutes"
        static let backgroundMode = "backgroundMode"
        static let animationIntensity = "animationIntensity"
        static let fontName = "fontName"
        static let fontSize = "fontSize"
        static let showClock = "showClock"
        static let showArtwork = "showArtwork"
        static let showTrackInfo = "showTrackInfo"
        static let artworkSize = "artworkSize"
        static let useArtworkColours = "useArtworkColours"
        static let lyricEffect = "lyricEffect"
        static let crossFadeSeconds = "crossFadeSeconds"
    }

    // MARK: - Energy

    /// How the display behaves while the overlay is showing.
    enum DisplayMode: String, CaseIterable {
        /// Never let the display sleep.
        case keepAwake
        /// Let the display sleep after the configured number of minutes.
        case sleepAfterMinutes

        var title: String {
            switch self {
            case .keepAwake: return "Mantener la pantalla encendida"
            case .sleepAfterMinutes: return "Apagar la pantalla después de un tiempo"
            }
        }
    }

    /// Whether the overlay shows at all.
    var overlayEnabled: Bool {
        get { defaults.object(forKey: "overlayEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "overlayEnabled") }
    }

    /// The display behaviour.
    var displayMode: DisplayMode {
        get {
            let raw = defaults.string(forKey: Key.displayMode) ?? DisplayMode.keepAwake.rawValue
            return DisplayMode(rawValue: raw) ?? .keepAwake
        }
        set { defaults.set(newValue.rawValue, forKey: Key.displayMode) }
    }

    /// How many minutes the display may stay on before it sleeps.
    var sleepAfterMinutes: Int {
        get {
            let value = defaults.object(forKey: Key.sleepAfterMinutes) as? Int ?? 5
            return [1, 5, 10, 15, 30, 60].contains(value) ? value : 5
        }
        set { defaults.set(newValue, forKey: Key.sleepAfterMinutes) }
    }

    /// The power mode to apply while the overlay is up.
    var powerMode: DisplayPower.Mode {
        switch displayMode {
        case .keepAwake:
            return .keepAwake
        case .sleepAfterMinutes:
            return .sleepAfter(minutes: sleepAfterMinutes)
        }
    }

    // MARK: - Background

    /// The background style.
    var backgroundMode: BackgroundView.Mode {
        get {
            let raw = defaults.string(forKey: Key.backgroundMode) ?? BackgroundView.Mode.glow.rawValue
            return BackgroundView.Mode(rawValue: raw) ?? .glow
        }
        set { defaults.set(newValue.rawValue, forKey: Key.backgroundMode) }
    }

    /// How fast the background animates, from 0 (still) to 2 (fast).
    var animationIntensity: Double {
        get {
            let value = defaults.object(forKey: Key.animationIntensity) as? Double ?? 1.0
            return min(max(value, 0), 2)
        }
        set { defaults.set(newValue, forKey: Key.animationIntensity) }
    }

    /// Whether the colours come from the album artwork.
    ///
    /// When off, a fixed accent colour is used instead.
    var useArtworkColours: Bool {
        get { defaults.object(forKey: Key.useArtworkColours) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.useArtworkColours) }
    }

    // MARK: - Lyrics

    /// How the active line is highlighted.
    ///
    /// The same enum drives the view and the settings, so there is a single
    /// definition of what each mode means.
    enum LyricEffect: String, CaseIterable {
        /// The whole line is lit.
        case line
        /// The word being sung fills in progressively.
        case word
        /// The word being sung swells, its neighbours taper off.
        case fisheye

        var title: String {
            switch self {
            case .line: return "Línea completa"
            case .word: return "Palabra a palabra"
            case .fisheye: return "Palabra destacada"
            }
        }
    }

    /// The lyrics font.
    var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? SystemFonts.defaultName }
        set { defaults.set(newValue, forKey: Key.fontName) }
    }

    /// The lyrics font size.
    var fontSize: Double {
        get {
            let value = defaults.object(forKey: Key.fontSize) as? Double ?? 38
            return min(max(value, 18), 88)
        }
        set { defaults.set(newValue, forKey: Key.fontSize) }
    }

    /// The highlight style.
    var lyricEffect: LyricEffect {
        get {
            let raw = defaults.string(forKey: Key.lyricEffect) ?? LyricEffect.word.rawValue
            return LyricEffect(rawValue: raw) ?? .word
        }
        set { defaults.set(newValue.rawValue, forKey: Key.lyricEffect) }
    }

    /// The font used for the lyrics.
    var lyricsFont: NSFont {
        SystemFonts.font(postScriptName: fontName, size: fontSize)
    }

    // MARK: - Content

    /// Whether the clock is shown.
    var showClock: Bool {
        get { defaults.object(forKey: Key.showClock) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showClock) }
    }

    /// Whether the album artwork is shown.
    var showArtwork: Bool {
        get { defaults.object(forKey: Key.showArtwork) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showArtwork) }
    }

    /// Whether the title and artist are shown.
    var showTrackInfo: Bool {
        get { defaults.object(forKey: Key.showTrackInfo) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showTrackInfo) }
    }

    /// The side length of the artwork, in points.
    var artworkSize: Double {
        get {
            let value = defaults.object(forKey: Key.artworkSize) as? Double ?? 340
            return min(max(value, 120), 520)
        }
        set { defaults.set(newValue, forKey: Key.artworkSize) }
    }

    /// How long the colour transition between tracks lasts, in seconds.
    var crossFadeSeconds: Double {
        get {
            let value = defaults.object(forKey: Key.crossFadeSeconds) as? Double ?? 1.2
            return min(max(value, 0), 4)
        }
        set { defaults.set(newValue, forKey: Key.crossFadeSeconds) }
    }
}
