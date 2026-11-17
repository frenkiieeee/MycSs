import Foundation

/// Puts settings back to their defaults. It removes the stored values of what a
/// style covers (`StyleDomain.keys`), so every property falls back to its own
/// default, and it can be undone with `PresetUndo`. The user's own styles, the
/// shortcut and the energy settings are not touched.
@MainActor
enum SettingsReset {

    static func reset(_ domains: [StyleDomain]) {
        PresetUndo.shared.run {
            for domain in domains {
                for key in domain.keys { UserDefaults.standard.removeObject(forKey: key) }
                StyleLibrary.shared.clearActive(domain)
            }
        }
    }
}
