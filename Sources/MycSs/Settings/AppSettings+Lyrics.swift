import AppKit
import Foundation
import SwiftUI

/// The lyrics screen: layout, font, highlight, background, content and animations.
extension AppSettings {

    // MARK: - Layout

    /// Whether the cover is on the right and the lyrics on the left.
    var coverOnRight: Bool {
        get { defaults.object(forKey: SettingKey.coverOnRight) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingKey.coverOnRight) }
    }

    // MARK: - Look of the lyrics

    /// Whether the lines far from the active one are drawn a little smaller and
    /// out of focus, the way Apple Music does it, so the one being sung stands
    /// out. The movement of the column is still a plain translation.
    var lyricsDepth: Bool {
        get { defaults.object(forKey: SettingKey.lyricsDepth) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.lyricsDepth) }
    }

    // MARK: - Background

    /// The background style.
    var backgroundMode: BackgroundView.Mode {
        get {
            let raw = defaults.string(forKey: SettingKey.backgroundMode) ?? BackgroundView.Mode.glow.rawValue
            return BackgroundView.Mode(rawValue: raw) ?? .glow
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.backgroundMode) }
    }

    /// How fast the background animates, from 0 (still) to 2 (fast).
    var animationIntensity: Double {
        get {
            let value = defaults.object(forKey: SettingKey.animationIntensity) as? Double ?? 1.0
            return min(max(value, 0), 2)
        }
        set { defaults.set(newValue, forKey: SettingKey.animationIntensity) }
    }

    /// Whether the colours come from the album artwork.
    ///
    /// When off, a fixed accent colour is used instead. This is the switch that
    /// makes the album's colours actually reach the screen.
    var useArtworkColours: Bool {
        get { defaults.object(forKey: SettingKey.useArtworkColours) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.useArtworkColours) }
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
    /// It cannot be named directly, CoreText refuses to hand out the system
    /// fonts by name, so it is represented by this sentinel and resolved
    /// through `NSFont.systemFont`.
    var fontName: String {
        get { defaults.string(forKey: SettingKey.fontName) ?? SystemFonts.systemFontSentinel }
        set { defaults.set(newValue, forKey: SettingKey.fontName) }
    }

    /// The lyrics font size.
    var fontSize: Double {
        get {
            let value = defaults.object(forKey: SettingKey.fontSize) as? Double ?? 42
            return min(max(value, 18), 88)
        }
        set { defaults.set(newValue, forKey: SettingKey.fontSize) }
    }

    /// The highlight style.
    var lyricEffect: LyricEffect {
        get {
            let raw = defaults.string(forKey: SettingKey.lyricEffect) ?? LyricEffect.word.rawValue
            return LyricEffect(rawValue: raw) ?? .word
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.lyricEffect) }
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
            let raw = defaults.string(forKey: SettingKey.wordTiming) ?? WordTiming.weighted.rawValue
            return WordTiming(rawValue: raw) ?? .weighted
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.wordTiming) }
    }

    /// The font used for the lyrics.
    var lyricsFont: NSFont {
        SystemFonts.font(postScriptName: fontName, size: fontSize)
    }

    // MARK: - Content

    /// Whether the clock is shown.
    var showClock: Bool {
        get { defaults.object(forKey: SettingKey.showClock) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.showClock) }
    }

    /// Whether the clock goes away a few seconds after the lyrics appear, so the
    /// screen is only the song. On by default.
    var clockAutoHide: Bool {
        get { defaults.object(forKey: SettingKey.clockAutoHide) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.clockAutoHide) }
    }

    /// How many seconds the clock stays before it goes.
    var clockAutoHideSeconds: Double {
        get { min(max(defaults.object(forKey: SettingKey.clockAutoHideSeconds) as? Double ?? 3, 1), 60) }
        set { defaults.set(newValue, forKey: SettingKey.clockAutoHideSeconds) }
    }

    /// Whether moving the mouse brings the clock back.
    var clockRevealOnMove: Bool {
        get { defaults.object(forKey: SettingKey.clockRevealOnMove) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingKey.clockRevealOnMove) }
    }

    /// Whether the album artwork is shown.
    var showArtwork: Bool {
        get { defaults.object(forKey: SettingKey.showArtwork) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.showArtwork) }
    }

    /// Whether the title and artist are shown.
    var showTrackInfo: Bool {
        get { defaults.object(forKey: SettingKey.showTrackInfo) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.showTrackInfo) }
    }

    /// The side length of the artwork, in points.
    var artworkSize: Double {
        get {
            let value = defaults.object(forKey: SettingKey.artworkSize) as? Double ?? 400
            return min(max(value, 160), 700)
        }
        set { defaults.set(newValue, forKey: SettingKey.artworkSize) }
    }

    /// How long the colour transition between tracks lasts, in seconds.
    var crossFadeSeconds: Double {
        get {
            let value = defaults.object(forKey: SettingKey.crossFadeSeconds) as? Double ?? 1.2
            return min(max(value, 0), 4)
        }
        set { defaults.set(newValue, forKey: SettingKey.crossFadeSeconds) }
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

    /// How the screen changes when the song does.
    enum SongTransition: String, CaseIterable {
        case off, fade, glide, cinematic

        var title: String {
            switch self {
            case .off: return "Sin animación"
            case .fade: return "Fundido"
            case .glide: return "Deslizar"
            case .cinematic: return "Cinematográfica"
            }
        }
    }

    var songTransition: SongTransition {
        get { SongTransition(rawValue: defaults.string(forKey: SettingKey.songTransition) ?? "") ?? .cinematic }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.songTransition) }
    }

    /// How long the change takes, in seconds.
    var songTransitionSeconds: Double {
        get { min(max(defaults.object(forKey: SettingKey.songTransitionSeconds) as? Double ?? 0.8, 0.25), 1.8) }
        set { defaults.set(newValue, forKey: SettingKey.songTransitionSeconds) }
    }

    /// The entrance animation.
    var entranceAnimation: Entrance {
        get {
            let raw = defaults.string(forKey: SettingKey.entranceAnimation) ?? Entrance.fade.rawValue
            return Entrance(rawValue: raw) ?? .fade
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.entranceAnimation) }
    }
}
