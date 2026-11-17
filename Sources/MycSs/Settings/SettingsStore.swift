import Foundation

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
