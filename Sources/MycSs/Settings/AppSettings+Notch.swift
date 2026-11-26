import AppKit
import Foundation
import SwiftUI

/// The notch: size, motion, look, volume and brightness indicator, widgets and notifications.
extension AppSettings {

    // MARK: - Notch

    /// Whether the notch shows the music. Off by default: it is new.
    var notchEnabled: Bool {
        get { defaults.object(forKey: SettingKey.notchEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingKey.notchEnabled) }
    }

    /// Whether the closed notch grows a little on both sides while music plays.
    var notchWings: Bool {
        get { defaults.object(forKey: SettingKey.notchWings) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchWings) }
    }

    /// Whether the notch widens for a few seconds when the song changes, to show
    /// the title and the artist.
    var notchPeek: Bool {
        get { defaults.object(forKey: SettingKey.notchPeek) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchPeek) }
    }

    /// Whether the open notch has the calendar tab.
    var notchCalendar: Bool {
        get { defaults.object(forKey: SettingKey.notchCalendar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchCalendar) }
    }

    /// Whether the notch folds back into the hardware one when nothing is playing.
    /// It stays a few seconds after a pause, so a short pause does not flicker it.
    var notchHideWhenIdle: Bool {
        get { defaults.object(forKey: SettingKey.notchHideWhenIdle) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchHideWhenIdle) }
    }

    /// Whether the volume and brightness keys are shown in the notch instead of
    /// by the system. It needs the Accessibility permission.
    var notchHUD: Bool {
        get { defaults.object(forKey: SettingKey.notchHUD) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchHUD) }
    }

    /// The identity (see `AppIdentity`) the Accessibility prompt was last shown
    /// for, so the app asks once for each identity and does not insist. A build
    /// signed another way is another identity, and the permission has to be asked
    /// for again anyway.
    var accessibilityPromptedFor: String {
        get { defaults.string(forKey: SettingKey.accessibilityPromptedFor) ?? "" }
        set { defaults.set(newValue, forKey: SettingKey.accessibilityPromptedFor) }
    }

    /// Whether the notch's bars follow the real sound. It needs the System Audio
    /// Recording permission.
    var notchReactive: Bool {
        get { defaults.object(forKey: SettingKey.notchReactive) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingKey.notchReactive) }
    }

    // MARK: - Notch: size, motion and style

    /// How big the open notch is, from 70 % to 130 % of its design size.
    var notchScale: Double {
        get { min(max(defaults.object(forKey: SettingKey.notchScale) as? Double ?? 0.86, 0.7), 1.3) }
        set { defaults.set(newValue, forKey: SettingKey.notchScale) }
    }

    /// How big the closed notch is: the width of its sides and what is drawn on
    /// them, from 50 % to 130 %. The height is the cut-out's own.
    var notchClosedScale: Double {
        get { min(max(defaults.object(forKey: SettingKey.notchClosedScale) as? Double ?? 0.72, 0.5), 1.3) }
        set { defaults.set(newValue, forKey: SettingKey.notchClosedScale) }
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
        get { NotchMotionStyle(rawValue: defaults.string(forKey: SettingKey.notchMotion) ?? "") ?? .smooth }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchMotion) }
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
        get { NotchOpenStyle(rawValue: defaults.string(forKey: SettingKey.notchOpenStyle) ?? "") ?? .sidesFirst }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchOpenStyle) }
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
        get { NotchPeekStyle(rawValue: defaults.string(forKey: SettingKey.notchPeekStyle) ?? "") ?? .sides }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchPeekStyle) }
    }

    /// On which screens the notch shows.
    enum NotchDisplays: String, CaseIterable {
        /// Only the screen of the Mac (the one with the notch).
        case builtIn
        /// Also on every other screen, as a pill at the top.
        case all

        var title: String {
            switch self {
            case .builtIn: return "Solo la pantalla de la Mac"
            case .all: return "Todas las pantallas"
            }
        }
    }

    var notchDisplays: NotchDisplays {
        get { NotchDisplays(rawValue: defaults.string(forKey: SettingKey.notchDisplays) ?? "") ?? .all }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchDisplays) }
    }

    /// How far the notch grows to each side for the new song, as a multiple of the
    /// default. It also scales the cover and the text that go on those sides.
    var notchPeekWidth: Double {
        get { min(max(defaults.object(forKey: SettingKey.notchPeekWidth) as? Double ?? 1.5, 0.6), 2.6) }
        set { defaults.set(newValue, forKey: SettingKey.notchPeekWidth) }
    }

    /// How long the notch stays open to the sides for the new song, in seconds.
    var notchPeekSeconds: Double {
        get { min(max(defaults.object(forKey: SettingKey.notchPeekSeconds) as? Double ?? 4.0, 1.5), 12) }
        set { defaults.set(newValue, forKey: SettingKey.notchPeekSeconds) }
    }

    /// How long the widening and the narrowing take, in seconds.
    var notchPeekDuration: Double {
        get { min(max(defaults.object(forKey: SettingKey.notchPeekDuration) as? Double ?? 0.7, 0.2), 1.8) }
        set { defaults.set(newValue, forKey: SettingKey.notchPeekDuration) }
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
        get { NotchVisualizerStyle(rawValue: defaults.string(forKey: SettingKey.notchVisualizerStyle) ?? "") ?? .bars }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchVisualizerStyle) }
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
        get { NotchHUDStyle(rawValue: defaults.string(forKey: SettingKey.notchHUDStyle) ?? "") ?? .bar }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchHUDStyle) }
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
        get { NotchHUDNumber(rawValue: defaults.string(forKey: SettingKey.notchHUDNumber) ?? "") ?? .counting }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchHUDNumber) }
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
        get { NotchHUDMotion(rawValue: defaults.string(forKey: SettingKey.notchHUDMotion) ?? "") ?? .smooth }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchHUDMotion) }
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
        get { NotchHUDEntrance(rawValue: defaults.string(forKey: SettingKey.notchHUDEntrance) ?? "") ?? .grow }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchHUDEntrance) }
    }

    /// Where the notch's accent colour comes from.
    enum NotchAccent: String, CaseIterable {
        case album, yellow, white
        case amber, sky, rose

        var title: String {
            switch self {
            case .album: return "Color del álbum"
            case .yellow: return "Amarillo MycSs"
            case .white: return "Blanco"
            case .amber: return "Ámbar"
            case .sky: return "Cielo"
            case .rose: return "Rosa"
            }
        }
    }

    // MARK: - Notch: surface (spec 016)

    /// What the notch is made of.
    enum NotchSurface: String, CaseIterable {
        /// Plain black, like the hardware notch.
        case solid
        /// See-through glass that blurs what is behind it.
        case glass
        /// Glass with the accent colour poured into it.
        case tinted

        var title: String {
            switch self {
            case .solid: return "Sólida"
            case .glass: return "Cristal"
            case .tinted: return "Cristal teñido"
            }
        }
    }

    var notchSurface: NotchSurface {
        get { NotchSurface(rawValue: defaults.string(forKey: SettingKey.notchSurface) ?? "") ?? .solid }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchSurface) }
    }

    /// How much the glass lets through, 0.15 (nearly black) to 0.95.
    var notchGlass: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchGlass) as? Double ?? 0.55, 0.15, 0.95) }
        set { defaults.set(Self.clamp(newValue, 0.15, 0.95), forKey: SettingKey.notchGlass) }
    }

    /// Multiplies the roundness of the notch's bottom corners.
    var notchCorner: Double {
        get { Self.clamp(defaults.object(forKey: SettingKey.notchCorner) as? Double ?? 1, 0.7, 1.5) }
        set { defaults.set(Self.clamp(newValue, 0.7, 1.5), forKey: SettingKey.notchCorner) }
    }

    /// How the timer widget asks for the time.
    enum NotchTimerStyle: String, CaseIterable {
        case presets, ruler

        var title: String {
            switch self {
            case .presets: return "Cuatro botones"
            case .ruler: return "Regla que se arrastra"
            }
        }
    }

    var notchTimerStyle: NotchTimerStyle {
        get { NotchTimerStyle(rawValue: defaults.string(forKey: SettingKey.notchTimerStyle) ?? "") ?? .presets }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchTimerStyle) }
    }

    var notchAccent: NotchAccent {
        get { NotchAccent(rawValue: defaults.string(forKey: SettingKey.notchAccent) ?? "") ?? .album }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchAccent) }
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
        get { NotchCoverShape(rawValue: defaults.string(forKey: SettingKey.notchCoverShape) ?? "") ?? .rounded }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchCoverShape) }
    }

    // MARK: - Notch: widgets and notifications

    /// What can sit on the right of the open notch's home page.
    enum NotchWidget: String, CaseIterable, Identifiable {
        case calendar, reminders, timer, system, clipboard
        /// The last notifications (spec 012).
        case notifications

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return "Calendario"
            case .reminders: return "Recordatorios"
            case .timer: return "Temporizador"
            case .system: return "Batería y sistema"
            case .clipboard: return "Portapapeles"
            case .notifications: return "Notificaciones"
            }
        }

        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            case .timer: return "timer"
            case .system: return "battery.75percent"
            case .clipboard: return "doc.on.clipboard"
            case .notifications: return "bell.badge"
            }
        }
    }

    /// The widgets the user wants, in order. The clipboard is off by default: it
    /// reads what the user copies, so it has to be turned on on purpose.
    var notchWidgets: [NotchWidget] {
        get {
            let raw = defaults.string(forKey: SettingKey.notchWidgets) ?? "calendar,reminders,timer,system"
            let list = raw.split(separator: ",").compactMap { NotchWidget(rawValue: String($0)) }
            return list.isEmpty ? [.calendar] : list
        }
        set { defaults.set(newValue.map(\.rawValue).joined(separator: ","), forKey: SettingKey.notchWidgets) }
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
        get { NotchWidget(rawValue: defaults.string(forKey: SettingKey.notchWidgetSelected) ?? "") ?? .calendar }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.notchWidgetSelected) }
    }

    /// Whether the notifications of other apps are shown in the notch. It needs
    /// the Full Disk Access permission, which is where macOS keeps them.
    var notchNotifications: Bool {
        get { defaults.object(forKey: SettingKey.notchNotifications) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.notchNotifications) }
    }

    /// Whether the menu bar icon is hidden. Only takes effect while the notch is on,
    /// because the notch is then the way back into the preferences.
    var hideMenuBarIcon: Bool {
        get { defaults.object(forKey: SettingKey.hideMenuBarIcon) as? Bool ?? false }
        set { defaults.set(newValue, forKey: SettingKey.hideMenuBarIcon) }
    }
}
