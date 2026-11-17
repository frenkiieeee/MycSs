import Foundation
import Observation

/// Remembers what the last preset changed, so «Deshacer» can put it back. It
/// compares the stored values before and after, so it does not need to know which
/// settings a preset touches.
@MainActor
@Observable
final class PresetUndo {
    static let shared = PresetUndo()

    private(set) var canUndo = false
    @ObservationIgnored private var saved: [String: Any?] = [:]

    func run(_ change: () -> Void) {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation()
        change()
        let after = defaults.dictionaryRepresentation()
        var changes: [String: Any?] = [:]
        for key in Set(before.keys).union(after.keys) {
            let old = before[key] as? NSObject
            let new = after[key] as? NSObject
            if old != new { changes[key] = before[key] }
        }
        // Two presets in a row: «Deshacer» goes back to before the first.
        if canUndo {
            for (key, value) in changes where saved.index(forKey: key) == nil { saved[key] = value }
        } else {
            saved = changes
        }
        canUndo = !saved.isEmpty
    }

    func undo() {
        let defaults = UserDefaults.standard
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        saved = [:]
        canUndo = false
    }
}
