import Foundation

/// The shortcut that moves the keyboard light (spec 011). It is not part of any style.
extension AppSettings {

    /// Whether the shortcuts for the keyboard light are on.
    var keyboardLightEnabled: Bool {
        get { defaults.object(forKey: SettingKey.keyboardLight) as? Bool ?? true }
        set { defaults.set(newValue, forKey: SettingKey.keyboardLight) }
    }

    /// The shortcut that raises the light: ⌥F2 until the user records another. `nil`
    /// is a shortcut the user cleared on purpose.
    var keyboardLightUp: KeyChord? {
        get { chord(SettingKey.keyboardLightUp, fallback: KeyboardLightDirection.defaultUp) }
        set { defaults.set(newValue?.stored ?? Self.noChord, forKey: SettingKey.keyboardLightUp) }
    }

    /// The shortcut that lowers the light: ⌥F1 until the user records another.
    var keyboardLightDown: KeyChord? {
        get { chord(SettingKey.keyboardLightDown, fallback: KeyboardLightDirection.defaultDown) }
        set { defaults.set(newValue?.stored ?? Self.noChord, forKey: SettingKey.keyboardLightDown) }
    }

    /// Puts both shortcuts back to ⌥F2 and ⌥F1.
    func resetKeyboardLightShortcuts() {
        UserDefaults.standard.removeObject(forKey: SettingKey.keyboardLightUp)
        UserDefaults.standard.removeObject(forKey: SettingKey.keyboardLightDown)
    }

    private static let noChord = "none"

    private func chord(_ key: String, fallback: KeyChord) -> KeyChord? {
        guard let text = defaults.string(forKey: key) else { return fallback }
        if text == Self.noChord { return nil }
        return KeyChord(stored: text) ?? fallback
    }
}
