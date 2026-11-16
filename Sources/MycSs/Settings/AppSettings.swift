import AppKit
import Foundation
import SwiftUI

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

    private let defaults = SettingsStore()

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

    // MARK: - Player

    /// Which player the lyrics follow.
    var playerPreference: PlayerHub.Preference {
        get {
            let raw = defaults.string(forKey: "playerPreference") ?? PlayerHub.Preference.automatic.rawValue
            return PlayerHub.Preference(rawValue: raw) ?? .automatic
        }
        set { defaults.set(newValue.rawValue, forKey: "playerPreference") }
    }

    // MARK: - Clock

    enum ClockWeight: String, CaseIterable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

        var weight: Font.Weight {
            switch self {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            }
        }

        var title: String {
            switch self {
            case .ultraLight: return "Ultrafina"
            case .thin: return "Fina"
            case .light: return "Ligera"
            case .regular: return "Normal"
            case .medium: return "Media"
            case .semibold: return "Seminegrita"
            case .bold: return "Negrita"
            case .heavy: return "Extranegrita"
            case .black: return "Black"
            }
        }
    }

    enum ClockDesign: String, CaseIterable {
        case standard, rounded, serif, monospaced

        var design: Font.Design {
            switch self {
            case .standard: return .default
            case .rounded: return .rounded
            case .serif: return .serif
            case .monospaced: return .monospaced
            }
        }

        var title: String {
            switch self {
            case .standard: return "SF Pro"
            case .rounded: return "SF Pro Rounded"
            case .serif: return "New York"
            case .monospaced: return "SF Mono"
            }
        }
    }

    enum ClockColor: String, CaseIterable {
        case white, glass, accent, yellow

        var title: String {
            switch self {
            case .white: return "Blanco"
            case .glass: return "Cristal"
            case .accent: return "Color del álbum"
            case .yellow: return "Amarillo MycSs"
            }
        }
    }

    enum ClockAlignment: String, CaseIterable {
        case centre, leading

        var title: String {
            switch self {
            case .centre: return "Centrado"
            case .leading: return "A la izquierda"
            }
        }
    }

    var clockWeight: ClockWeight {
        get { ClockWeight(rawValue: defaults.string(forKey: "clockWeight") ?? "") ?? .light }
        set { defaults.set(newValue.rawValue, forKey: "clockWeight") }
    }

    var clockDesign: ClockDesign {
        get { ClockDesign(rawValue: defaults.string(forKey: "clockDesign") ?? "") ?? .rounded }
        set { defaults.set(newValue.rawValue, forKey: "clockDesign") }
    }

    var clockColor: ClockColor {
        get { ClockColor(rawValue: defaults.string(forKey: "clockColor") ?? "") ?? .white }
        set { defaults.set(newValue.rawValue, forKey: "clockColor") }
    }

    var clockAlignment: ClockAlignment {
        get { ClockAlignment(rawValue: defaults.string(forKey: "clockAlignment") ?? "") ?? .centre }
        set { defaults.set(newValue.rawValue, forKey: "clockAlignment") }
    }

    /// The size of the time, in points. The date follows it.
    var clockSize: Double {
        get { min(max(defaults.object(forKey: "clockSize") as? Double ?? 104, 48), 200) }
        set { defaults.set(newValue, forKey: "clockSize") }
    }

    var clockShowDate: Bool {
        get { defaults.object(forKey: "clockShowDate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "clockShowDate") }
    }

    // MARK: - Layout

    /// Whether the cover is on the right and the lyrics on the left.
    var coverOnRight: Bool {
        get { defaults.object(forKey: "coverOnRight") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "coverOnRight") }
    }

    // MARK: - Look of the lyrics

    /// Whether the lines far from the active one are drawn a little smaller and
    /// out of focus, the way Apple Music does it, so the one being sung stands
    /// out. The movement of the column is still a plain translation.
    var lyricsDepth: Bool {
        get { defaults.object(forKey: "lyricsDepth") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "lyricsDepth") }
    }

    // MARK: - Notch

    /// Whether the notch shows the music. Off by default: it is new.
    var notchEnabled: Bool {
        get { defaults.object(forKey: "notchEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notchEnabled") }
    }

    /// Whether the closed notch grows a little on both sides while music plays.
    var notchWings: Bool {
        get { defaults.object(forKey: "notchWings") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchWings") }
    }

    /// Whether the notch widens for a few seconds when the song changes, to show
    /// the title and the artist.
    var notchPeek: Bool {
        get { defaults.object(forKey: "notchPeek") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchPeek") }
    }

    /// Whether the open notch has the calendar tab.
    var notchCalendar: Bool {
        get { defaults.object(forKey: "notchCalendar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchCalendar") }
    }

    /// Whether the notch folds back into the hardware one when nothing is playing.
    /// It stays a few seconds after a pause, so a short pause does not flicker it.
    var notchHideWhenIdle: Bool {
        get { defaults.object(forKey: "notchHideWhenIdle") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchHideWhenIdle") }
    }

    /// Whether the volume and brightness keys are shown in the notch instead of
    /// by the system. It needs the Accessibility permission.
    var notchHUD: Bool {
        get { defaults.object(forKey: "notchHUD") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchHUD") }
    }

    /// The identity (see `AppIdentity`) the Accessibility prompt was last shown
    /// for, so the app asks once for each identity and does not insist. A build
    /// signed another way is another identity, and the permission has to be asked
    /// for again anyway.
    var accessibilityPromptedFor: String {
        get { defaults.string(forKey: "accessibilityPromptedFor") ?? "" }
        set { defaults.set(newValue, forKey: "accessibilityPromptedFor") }
    }

    /// Whether the notch's bars follow the real sound. It needs the System Audio
    /// Recording permission.
    var notchReactive: Bool {
        get { defaults.object(forKey: "notchReactive") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notchReactive") }
    }

    // MARK: - Notch: size, motion and style

    /// How big the open notch is, from 70 % to 130 % of its design size.
    var notchScale: Double {
        get { min(max(defaults.object(forKey: "notchScale") as? Double ?? 0.86, 0.7), 1.3) }
        set { defaults.set(newValue, forKey: "notchScale") }
    }

    /// How big the closed notch is: the width of its sides and what is drawn on
    /// them, from 50 % to 130 %. The height is the cut-out's own.
    var notchClosedScale: Double {
        get { min(max(defaults.object(forKey: "notchClosedScale") as? Double ?? 0.72, 0.5), 1.3) }
        set { defaults.set(newValue, forKey: "notchClosedScale") }
    }

    /// The feel of the notch's movement.
    enum NotchMotionStyle: String, CaseIterable {
        case smooth, bouncy, snappy, slow

        var title: String {
            switch self {
            case .smooth: return "Suave"
            case .bouncy: return "Elástica"
            case .snappy: return "Rápida"
            case .slow: return "Lenta"
            }
        }
    }

    var notchMotion: NotchMotionStyle {
        get { NotchMotionStyle(rawValue: defaults.string(forKey: "notchMotion") ?? "") ?? .smooth }
        set { defaults.set(newValue.rawValue, forKey: "notchMotion") }
    }

    /// How the notch opens.
    enum NotchOpenStyle: String, CaseIterable {
        /// Width and height grow together.
        case together
        /// First to the sides, then down.
        case sidesFirst

        var title: String {
            switch self {
            case .together: return "A la vez"
            case .sidesFirst: return "Primero a los lados, luego hacia abajo"
            }
        }
    }

    var notchOpenStyle: NotchOpenStyle {
        get { NotchOpenStyle(rawValue: defaults.string(forKey: "notchOpenStyle") ?? "") ?? .sidesFirst }
        set { defaults.set(newValue.rawValue, forKey: "notchOpenStyle") }
    }

    /// How the title shows when the song changes.
    enum NotchPeekStyle: String, CaseIterable {
        /// The notch grows to the sides and the title goes beside the cut-out.
        case sides
        /// The notch grows down and the title goes under the cut-out.
        case drop

        var title: String {
            switch self {
            case .sides: return "Hacia los lados"
            case .drop: return "Hacia abajo"
            }
        }
    }

    var notchPeekStyle: NotchPeekStyle {
        get { NotchPeekStyle(rawValue: defaults.string(forKey: "notchPeekStyle") ?? "") ?? .sides }
        set { defaults.set(newValue.rawValue, forKey: "notchPeekStyle") }
    }

    /// How far the notch grows to each side for the new song, as a multiple of the
    /// default. It also scales the cover and the text that go on those sides.
    var notchPeekWidth: Double {
        get { min(max(defaults.object(forKey: "notchPeekWidth") as? Double ?? 1.5, 0.6), 2.6) }
        set { defaults.set(newValue, forKey: "notchPeekWidth") }
    }

    /// How long the notch stays open to the sides for the new song, in seconds.
    var notchPeekSeconds: Double {
        get { min(max(defaults.object(forKey: "notchPeekSeconds") as? Double ?? 4.0, 1.5), 12) }
        set { defaults.set(newValue, forKey: "notchPeekSeconds") }
    }

    /// How long the widening and the narrowing take, in seconds.
    var notchPeekDuration: Double {
        get { min(max(defaults.object(forKey: "notchPeekDuration") as? Double ?? 0.7, 0.2), 1.8) }
        set { defaults.set(newValue, forKey: "notchPeekDuration") }
    }

    enum NotchVisualizerStyle: String, CaseIterable {
        case bars, wave, dots, off

        var title: String {
            switch self {
            case .bars: return "Barras"
            case .wave: return "Onda"
            case .dots: return "Puntos"
            case .off: return "Ninguno"
            }
        }
    }

    var notchVisualizerStyle: NotchVisualizerStyle {
        get { NotchVisualizerStyle(rawValue: defaults.string(forKey: "notchVisualizerStyle") ?? "") ?? .bars }
        set { defaults.set(newValue.rawValue, forKey: "notchVisualizerStyle") }
    }

    /// How the volume and brightness are drawn.
    enum NotchHUDStyle: String, CaseIterable {
        case bar, minimal, ring
        /// A bar with a knob that slides along it, like a slider.
        case slider
        /// Ten little bars that fill one after the other.
        case segments

        var title: String {
            switch self {
            case .bar: return "Barra"
            case .slider: return "Deslizador"
            case .ring: return "Anillo"
            case .segments: return "Segmentos"
            case .minimal: return "Solo el número"
            }
        }
    }

    var notchHUDStyle: NotchHUDStyle {
        get { NotchHUDStyle(rawValue: defaults.string(forKey: "notchHUDStyle") ?? "") ?? .bar }
        set { defaults.set(newValue.rawValue, forKey: "notchHUDStyle") }
    }

    /// How the number of the indicator behaves.
    enum NotchHUDNumber: String, CaseIterable {
        /// It counts through every value on the way, like an odometer.
        case counting
        /// The digits roll over.
        case wheel
        case fixed
        case hidden

        var title: String {
            switch self {
            case .counting: return "Cuenta paso a paso"
            case .wheel: return "Dígitos que ruedan"
            case .fixed: return "Fijo"
            case .hidden: return "Oculto"
            }
        }
    }

    var notchHUDNumber: NotchHUDNumber {
        get { NotchHUDNumber(rawValue: defaults.string(forKey: "notchHUDNumber") ?? "") ?? .counting }
        set { defaults.set(newValue.rawValue, forKey: "notchHUDNumber") }
    }

    /// How the bar, the ring or the knob travel from one value to the next.
    enum NotchHUDMotion: String, CaseIterable {
        case smooth, elastic, glide

        var title: String {
            switch self {
            case .smooth: return "Suave"
            case .elastic: return "Elástico"
            case .glide: return "Deslizante"
            }
        }
    }

    var notchHUDMotion: NotchHUDMotion {
        get { NotchHUDMotion(rawValue: defaults.string(forKey: "notchHUDMotion") ?? "") ?? .smooth }
        set { defaults.set(newValue.rawValue, forKey: "notchHUDMotion") }
    }

    /// How the indicator comes in and goes out.
    enum NotchHUDEntrance: String, CaseIterable {
        /// The notch widens and the indicator comes out of it.
        case grow
        /// A little bounce.
        case pop
        case slide
        case fade

        var title: String {
            switch self {
            case .grow: return "Crece desde el notch"
            case .pop: return "Rebote"
            case .slide: return "Desliza desde arriba"
            case .fade: return "Fundido"
            }
        }
    }

    var notchHUDEntrance: NotchHUDEntrance {
        get { NotchHUDEntrance(rawValue: defaults.string(forKey: "notchHUDEntrance") ?? "") ?? .grow }
        set { defaults.set(newValue.rawValue, forKey: "notchHUDEntrance") }
    }

    /// Where the notch's accent colour comes from.
    enum NotchAccent: String, CaseIterable {
        case album, yellow, white

        var title: String {
            switch self {
            case .album: return "Color del álbum"
            case .yellow: return "Amarillo MycSs"
            case .white: return "Blanco"
            }
        }
    }

    var notchAccent: NotchAccent {
        get { NotchAccent(rawValue: defaults.string(forKey: "notchAccent") ?? "") ?? .album }
        set { defaults.set(newValue.rawValue, forKey: "notchAccent") }
    }

    enum NotchCoverShape: String, CaseIterable {
        case rounded
        /// A circle that turns like a record while the music plays.
        case vinyl

        var title: String {
            switch self {
            case .rounded: return "Cuadrada"
            case .vinyl: return "Disco que gira"
            }
        }
    }

    var notchCoverShape: NotchCoverShape {
        get { NotchCoverShape(rawValue: defaults.string(forKey: "notchCoverShape") ?? "") ?? .rounded }
        set { defaults.set(newValue.rawValue, forKey: "notchCoverShape") }
    }

    // MARK: - Notch: widgets and notifications

    /// What can sit on the right of the open notch's home page.
    enum NotchWidget: String, CaseIterable, Identifiable {
        case calendar, reminders, timer, system, clipboard

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "Calendario"
            case .reminders: return "Recordatorios"
            case .timer: return "Temporizador"
            case .system: return "Batería y sistema"
            case .clipboard: return "Portapapeles"
            }
        }

        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            case .timer: return "timer"
            case .system: return "battery.75percent"
            case .clipboard: return "doc.on.clipboard"
            }
        }
    }

    /// The widgets the user wants, in order. The clipboard is off by default: it
    /// reads what the user copies, so it has to be turned on on purpose.
    var notchWidgets: [NotchWidget] {
        get {
            let raw = defaults.string(forKey: "notchWidgets") ?? "calendar,reminders,timer,system"
            let list = raw.split(separator: ",").compactMap { NotchWidget(rawValue: String($0)) }
            return list.isEmpty ? [.calendar] : list
        }
        set { defaults.set(newValue.map(\.rawValue).joined(separator: ","), forKey: "notchWidgets") }
    }

    func isNotchWidgetOn(_ widget: NotchWidget) -> Bool { notchWidgets.contains(widget) }

    func setNotchWidget(_ widget: NotchWidget, on: Bool) {
        var list = notchWidgets
        if on, !list.contains(widget) { list.append(widget) }
        if !on { list.removeAll { $0 == widget } }
        notchWidgets = list.isEmpty ? [.calendar] : list
    }

    /// The widget that was open last.
    var notchWidgetSelected: NotchWidget {
        get { NotchWidget(rawValue: defaults.string(forKey: "notchWidgetSelected") ?? "") ?? .calendar }
        set { defaults.set(newValue.rawValue, forKey: "notchWidgetSelected") }
    }

    /// Whether the notifications of other apps are shown in the notch. It needs
    /// the Full Disk Access permission, which is where macOS keeps them.
    var notchNotifications: Bool {
        get { defaults.object(forKey: "notchNotifications") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notchNotifications") }
    }

    /// Whether the menu bar icon is hidden. Only takes effect while the notch is on,
    /// because the notch is then the way back into the preferences.
    var hideMenuBarIcon: Bool {
        get { defaults.object(forKey: "hideMenuBarIcon") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hideMenuBarIcon") }
    }

    // MARK: - Player and leaving

    /// Whether the player controls (previous, play, next, progress) are shown.
    var showPlayerControls: Bool {
        get { defaults.object(forKey: "showPlayerControls") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showPlayerControls") }
    }

    /// Whether the cover moves to the middle of the screen when a song has no
    /// lyrics, instead of staying on the left next to an empty column.
    var centerCoverWithoutLyrics: Bool {
        get { defaults.object(forKey: "centerCoverWithoutLyrics") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "centerCoverWithoutLyrics") }
    }

    /// Whether Escape or a click outside the lyrics closes the overlay, on the
    /// lock screen and in the full screen lyrics.
    var dismissOnEscapeOrClick: Bool {
        get { defaults.object(forKey: "dismissOnEscapeOrClick") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dismissOnEscapeOrClick") }
    }

    // MARK: - Lyrics anywhere

    /// Whether the global shortcut that shows the lyrics is on.
    var hotKeyEnabled: Bool {
        get { defaults.object(forKey: "hotKeyEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hotKeyEnabled") }
    }

    /// The virtual key code of the shortcut. The default is the key L.
    var hotKeyCode: Int {
        get { defaults.object(forKey: "hotKeyCode") as? Int ?? 37 }
        set { defaults.set(newValue, forKey: "hotKeyCode") }
    }

    /// The Carbon modifier bits of the shortcut. The default is Control + Option.
    var hotKeyModifiers: Int {
        get { defaults.object(forKey: "hotKeyModifiers") as? Int ?? 6144 }
        set { defaults.set(newValue, forKey: "hotKeyModifiers") }
    }

    /// The shortcut as the user reads it ("⌃⌥L").
    var hotKeyLabel: String {
        get { defaults.string(forKey: "hotKeyLabel") ?? "⌃⌥L" }
        set { defaults.set(newValue, forKey: "hotKeyLabel") }
    }

    /// The character of the shortcut, lowercase, for the menu item.
    var hotKeyCharacter: String {
        get { defaults.string(forKey: "hotKeyCharacter") ?? "l" }
        set { defaults.set(newValue, forKey: "hotKeyCharacter") }
    }

    /// After how many idle minutes the lyrics appear on their own while music is
    /// playing. 0 means never.
    var idleMinutes: Int {
        get {
            let value = defaults.object(forKey: "idleMinutes") as? Int ?? 0
            return [0, 1, 2, 5, 10, 15, 30].contains(value) ? value : 0
        }
        set { defaults.set(newValue, forKey: "idleMinutes") }
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

    /// Whether the clock goes away a few seconds after the lyrics appear, so the
    /// screen is only the song. On by default.
    var clockAutoHide: Bool {
        get { defaults.object(forKey: "clockAutoHide") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "clockAutoHide") }
    }

    /// How many seconds the clock stays before it goes.
    var clockAutoHideSeconds: Double {
        get { min(max(defaults.object(forKey: "clockAutoHideSeconds") as? Double ?? 3, 1), 60) }
        set { defaults.set(newValue, forKey: "clockAutoHideSeconds") }
    }

    /// Whether moving the mouse brings the clock back.
    var clockRevealOnMove: Bool {
        get { defaults.object(forKey: "clockRevealOnMove") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "clockRevealOnMove") }
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
        get { SongTransition(rawValue: defaults.string(forKey: "songTransition") ?? "") ?? .cinematic }
        set { defaults.set(newValue.rawValue, forKey: "songTransition") }
    }

    /// How long the change takes, in seconds.
    var songTransitionSeconds: Double {
        get { min(max(defaults.object(forKey: "songTransitionSeconds") as? Double ?? 0.8, 0.25), 1.8) }
        set { defaults.set(newValue, forKey: "songTransitionSeconds") }
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


// MARK: - Store with a temporary layer

/// A layer of values that, while it is on, is read instead of the saved settings. It
/// is how a style is **seen without being applied**: the preview draws one frame
/// with the layer on, in one go on the main thread, and takes it off again.
enum SettingsOverride {
    /// The values to read instead; a key present with `nil` means "its default".
    nonisolated(unsafe) static var values: [String: Any?]?
    /// While on, a write goes into the layer and not into the saved settings. It is
    /// how a ready-made style says what it would change.
    nonisolated(unsafe) static var capturing = false

    /// What `change` would write, without writing it.
    static func capture(_ change: () -> Void) -> [String: Any?] {
        values = [:]
        capturing = true
        change()
        capturing = false
        let result = values ?? [:]
        values = nil
        return result
    }
}

/// The saved settings, with the temporary layer on top.
struct SettingsStore {
    private let base = UserDefaults.standard

    func object(forKey key: String) -> Any? {
        if let layer = SettingsOverride.values, let entry = layer[key] { return entry }
        return base.object(forKey: key)
    }

    func string(forKey key: String) -> String? {
        object(forKey: key) as? String
    }

    func set(_ value: Any?, forKey key: String) {
        if SettingsOverride.capturing {
            SettingsOverride.values?[key] = .some(value)
        } else {
            base.set(value, forKey: key)
        }
    }
}
