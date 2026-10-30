import AppKit
import Foundation

/// The user's settings.
///
/// Stored in `UserDefaults` under the app's own domain. Every value has a
/// sensible default, so a fresh install works without any configuration.
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
        static let entranceAnimation = "entranceAnimation"
        static let wordTiming = "wordTiming"
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
    /// When off, a fixed accent colour is used instead. This is the switch that
    /// makes the album's colours actually reach the screen.
    var useArtworkColours: Bool {
        get { defaults.object(forKey: Key.useArtworkColours) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.useArtworkColours) }
    }

    // MARK: - Lyrics

    /// How the active line is highlighted.
    enum LyricEffect: String, CaseIterable {
        /// The whole line is lit at once.
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
    ///
    /// The default is the system font, which is Apple's own typeface (SF Pro).
    /// It cannot be named directly — CoreText refuses to hand out the system
    /// fonts by name — so it is represented by this sentinel and resolved
    /// through `NSFont.systemFont`.
    var fontName: String {
        get { defaults.string(forKey: Key.fontName) ?? SystemFonts.systemFontSentinel }
        set { defaults.set(newValue, forKey: Key.fontName) }
    }

    /// The lyrics font size.
    var fontSize: Double {
        get {
            let value = defaults.object(forKey: Key.fontSize) as? Double ?? 42
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

    /// How the words are timed.
    enum WordTiming: String, CaseIterable {
        /// The words are spread evenly inside their line.
        case even
        /// The words are spread following the natural length of each word, so a
        /// long word gets more time than a short one.
        case weighted

        var title: String {
            switch self {
            case .even: return "Proporcional a la longitud"
            case .weighted: return "Proporcional a la letra"
            }
        }
    }

    /// How the words inside a line are distributed.
    var wordTiming: WordTiming {
        get {
            let raw = defaults.string(forKey: Key.wordTiming) ?? WordTiming.weighted.rawValue
            return WordTiming(rawValue: raw) ?? .weighted
        }
        set { defaults.set(newValue.rawValue, forKey: Key.wordTiming) }
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
        get { defaults.object(forKey: Key.showTrackInfo) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showTrackInfo) }
    }

    /// The side length of the artwork, in points.
    var artworkSize: Double {
        get {
            let value = defaults.object(forKey: Key.artworkSize) as? Double ?? 400
            return min(max(value, 160), 700)
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

    // MARK: - Entrance

    /// How the overlay appears when the screen is locked.
    enum Entrance: String, CaseIterable {
        /// The overlay fades in and grows slightly.
        case fade
        /// The overlay falls in from the top.
        case fall
        /// The overlay rises from the bottom.
        case rise

        var title: String {
            switch self {
            case .fade: return "Aparecer suave"
            case .fall: return "Caer desde arriba"
            case .rise: return "Subir desde abajo"
            }
        }
    }

    /// The entrance animation.
    var entranceAnimation: Entrance {
        get {
            let raw = defaults.string(forKey: Key.entranceAnimation) ?? Entrance.fade.rawValue
            return Entrance(rawValue: raw) ?? .fade
        }
        set { defaults.set(newValue.rawValue, forKey: Key.entranceAnimation) }
    }
}
