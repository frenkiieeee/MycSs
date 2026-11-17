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

    let defaults = SettingsStore()

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
        get { defaults.object(forKey: SettingKey.overlayEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.overlayEnabled) }
    }

    /// The display behaviour.
    var displayMode: DisplayMode {
        get {
            let raw = defaults.string(forKey: SettingKey.displayMode) ?? DisplayMode.keepAwake.rawValue
            return DisplayMode(rawValue: raw) ?? .keepAwake
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.displayMode) }
    }

    /// How many minutes the display may stay on before it sleeps.
    var sleepAfterMinutes: Int {
        get {
            let value = defaults.object(forKey: SettingKey.sleepAfterMinutes) as? Int ?? 5
            return [1, 5, 10, 15, 30, 60].contains(value) ? value : 5
        }
        set { defaults.set(newValue, forKey: SettingKey.sleepAfterMinutes) }
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
            let raw = defaults.string(forKey: SettingKey.playerPreference) ?? PlayerHub.Preference.automatic.rawValue
            return PlayerHub.Preference(rawValue: raw) ?? .automatic
        }
        set { defaults.set(newValue.rawValue, forKey: SettingKey.playerPreference) }
    }

    // MARK: - Player and leaving

    /// Whether the player controls (previous, play, next, progress) are shown.
    var showPlayerControls: Bool {
        get { defaults.object(forKey: SettingKey.showPlayerControls) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.showPlayerControls) }
    }

    /// Whether the cover moves to the middle of the screen when a song has no
    /// lyrics, instead of staying on the left next to an empty column.
    var centerCoverWithoutLyrics: Bool {
        get { defaults.object(forKey: SettingKey.centerCoverWithoutLyrics) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.centerCoverWithoutLyrics) }
    }

    /// Whether Escape or a click outside the lyrics closes the overlay, on the
    /// lock screen and in the full screen lyrics.
    var dismissOnEscapeOrClick: Bool {
        get { defaults.object(forKey: SettingKey.dismissOnEscapeOrClick) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.dismissOnEscapeOrClick) }
    }

    // MARK: - Lyrics anywhere

    /// Whether the global shortcut that shows the lyrics is on.
    var hotKeyEnabled: Bool {
        get { defaults.object(forKey: SettingKey.hotKeyEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.hotKeyEnabled) }
    }

    /// The virtual key code of the shortcut. The default is the key L.
    var hotKeyCode: Int {
        get { defaults.object(forKey: SettingKey.hotKeyCode) as? Int ?? 37 }
        set { defaults.set(newValue, forKey: SettingKey.hotKeyCode) }
    }

    /// The Carbon modifier bits of the shortcut. The default is Control + Option.
    var hotKeyModifiers: Int {
        get { defaults.object(forKey: SettingKey.hotKeyModifiers) as? Int ?? 6144 }
        set { defaults.set(newValue, forKey: SettingKey.hotKeyModifiers) }
    }

    /// The shortcut as the user reads it ("⌃⌥L").
    var hotKeyLabel: String {
        get { defaults.string(forKey: SettingKey.hotKeyLabel) ?? "⌃⌥L" }
        set { defaults.set(newValue, forKey: SettingKey.hotKeyLabel) }
    }

    /// The character of the shortcut, lowercase, for the menu item.
    var hotKeyCharacter: String {
        get { defaults.string(forKey: SettingKey.hotKeyCharacter) ?? "l" }
        set { defaults.set(newValue, forKey: SettingKey.hotKeyCharacter) }
    }

    /// After how many idle minutes the lyrics appear on their own while music is
    /// playing. 0 means never.
    var idleMinutes: Int {
        get {
            let value = defaults.object(forKey: SettingKey.idleMinutes) as? Int ?? 0
            return [0, 1, 2, 5, 10, 15, 30].contains(value) ? value : 0
        }
        set { defaults.set(newValue, forKey: SettingKey.idleMinutes) }
    }
}
