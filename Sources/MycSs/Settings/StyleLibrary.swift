import Foundation
import Observation

// MARK: - Styles of the user

/// What a style covers: the lyrics screen, or the notch.
enum StyleDomain: String {
    case lyrics, notch

    /// The settings a style of this kind stores. Applying a style sets all of them,
    /// so a custom style is a complete picture, not a patch.
    var keys: [String] {
        switch self {
        case .lyrics:
            return [
                SettingKey.backgroundMode, SettingKey.animationIntensity, SettingKey.fontName, SettingKey.fontSize,
                SettingKey.showClock, SettingKey.showArtwork, SettingKey.showTrackInfo, SettingKey.artworkSize,
                SettingKey.useArtworkColours, SettingKey.lyricEffect, SettingKey.crossFadeSeconds,
                SettingKey.entranceAnimation, SettingKey.songTransition, SettingKey.songTransitionSeconds, SettingKey.wordTiming, SettingKey.clockAlignment, SettingKey.clockColor,
                SettingKey.clockDesign, SettingKey.clockShowDate, SettingKey.clockSize, SettingKey.clockWeight,
                SettingKey.clockAutoHide, SettingKey.clockAutoHideSeconds, SettingKey.clockRevealOnMove,
                SettingKey.coverOnRight, SettingKey.lyricsDepth, SettingKey.showPlayerControls,
                SettingKey.centerCoverWithoutLyrics,
            ]
        case .notch:
            return [
                SettingKey.notchScale, SettingKey.notchClosedScale, SettingKey.notchMotion, SettingKey.notchOpenStyle,
                SettingKey.notchPeekStyle, SettingKey.notchPeekWidth, SettingKey.notchPeekSeconds, SettingKey.notchPeekDuration, SettingKey.notchVisualizerStyle, SettingKey.notchHUDStyle,
                SettingKey.notchHUDNumber, SettingKey.notchHUDMotion, SettingKey.notchHUDEntrance,
                SettingKey.notchAccent, SettingKey.notchCoverShape, SettingKey.notchWings, SettingKey.notchPeek,
                SettingKey.notchWidgets, SettingKey.notchSurface, SettingKey.notchGlass, SettingKey.notchCorner,
                SettingKey.notchTimerStyle,
            ]
        }
    }
}

/// A style, ready-made or made by the user.
struct StyleItem: Identifiable {
    let id: String
    let title: String
    let summary: String
    let isBuiltIn: Bool
}

/// The styles of the user, and which one is in use.
///
/// A custom style is a snapshot of the settings of its kind. «En uso» means the
/// settings still match what the style stored when it was applied; if one is
/// changed afterwards the style shows as «Modificado».
@MainActor
@Observable
final class StyleLibrary {
    static let shared = StyleLibrary()

    private struct Custom {
        var id: String
        var domain: StyleDomain
        var name: String
        var values: [String: Any]
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let storeKey = "customStyles"

    /// The name being typed for a new style.
    var draftName = ""
    /// The style being renamed, if any, and its new name.
    var editingID: String?
    var editName = ""

    // MARK: Reading

    private func load() -> [Custom] {
        let raw = defaults.array(forKey: storeKey) as? [[String: Any]] ?? []
        return raw.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let name = entry["name"] as? String,
                  let domain = (entry["domain"] as? String).flatMap(StyleDomain.init(rawValue:)),
                  let values = entry["values"] as? [String: Any]
            else { return nil }
            return Custom(id: id, domain: domain, name: name, values: values)
        }
    }

    private func save(_ list: [Custom]) {
        defaults.set(list.map { ["id": $0.id, "name": $0.name, "domain": $0.domain.rawValue, "values": $0.values] as [String: Any] },
                     forKey: storeKey)
    }

    /// Every style of a kind: the ready-made ones, then the user's.
    func items(_ domain: StyleDomain) -> [StyleItem] {
        var result: [StyleItem]
        switch domain {
        case .lyrics:
            result = StylePreset.allCases.map {
                StyleItem(id: "builtin." + $0.rawValue, title: $0.title, summary: $0.summary, isBuiltIn: true)
            }
        case .notch:
            result = NotchLook.allCases.map {
                StyleItem(id: "builtin." + $0.rawValue, title: $0.title, summary: $0.summary, isBuiltIn: true)
            }
        }
        for custom in load() where custom.domain == domain {
            result.append(StyleItem(id: custom.id, title: custom.name, summary: "Estilo propio", isBuiltIn: false))
        }
        return result
    }

    // MARK: What is in use

    private func snapshot(_ domain: StyleDomain) -> [String: Any] {
        var values: [String: Any] = [:]
        for key in domain.keys {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return values
    }

    /// Forgets which style is in use (after the settings go back to their defaults).
    func clearActive(_ domain: StyleDomain) {
        defaults.removeObject(forKey: activeKey(domain))
        defaults.removeObject(forKey: activeValuesKey(domain))
    }

    private func activeKey(_ domain: StyleDomain) -> String { "activeStyle." + domain.rawValue }
    private func activeValuesKey(_ domain: StyleDomain) -> String { "activeStyleValues." + domain.rawValue }

    private func markActive(_ id: String, _ domain: StyleDomain) {
        defaults.set(id, forKey: activeKey(domain))
        defaults.set(snapshot(domain), forKey: activeValuesKey(domain))
    }

    enum State { case inactive, active, modified }

    func state(of id: String, _ domain: StyleDomain) -> State {
        guard defaults.string(forKey: activeKey(domain)) == id else { return .inactive }
        let stored = defaults.dictionary(forKey: activeValuesKey(domain)) ?? [:]
        return NSDictionary(dictionary: stored).isEqual(to: snapshot(domain)) ? .active : .modified
    }

    // MARK: Seeing without applying

    /// The settings a style would put, to draw it without applying it. A ready-made
    /// style says what it writes; a custom one is complete for its kind.
    func previewValues(_ id: String, _ domain: StyleDomain) -> [String: Any?] {
        if id.hasPrefix("builtin.") {
            let raw = String(id.dropFirst("builtin.".count))
            let settings = AppSettings.shared
            return SettingsOverride.capture {
                switch domain {
                case .lyrics: StylePreset(rawValue: raw)?.apply(to: settings)
                case .notch: NotchLook(rawValue: raw)?.apply(to: settings)
                }
            }
        }
        guard let custom = load().first(where: { $0.id == id }) else { return [:] }
        var layer: [String: Any?] = [:]
        for key in domain.keys { layer[key] = .some(custom.values[key]) }
        return layer
    }

    // MARK: Changing

    func apply(_ id: String, _ domain: StyleDomain) {
        PresetUndo.shared.run {
            let settings = AppSettings.shared
            if id.hasPrefix("builtin.") {
                let raw = String(id.dropFirst("builtin.".count))
                switch domain {
                case .lyrics: StylePreset(rawValue: raw)?.apply(to: settings)
                case .notch: NotchLook(rawValue: raw)?.apply(to: settings)
                }
            } else if let custom = load().first(where: { $0.id == id }) {
                for key in domain.keys {
                    if let value = custom.values[key] {
                        defaults.set(value, forKey: key)
                    } else {
                        defaults.removeObject(forKey: key)
                    }
                }
            }
            markActive(id, domain)
        }
    }

    /// Saves what the settings are now as a new style, and marks it as in use.
    func createFromCurrent(_ domain: StyleDomain) {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var list = load()
        let custom = Custom(id: UUID().uuidString, domain: domain, name: name, values: snapshot(domain))
        list.append(custom)
        save(list)
        markActive(custom.id, domain)
        draftName = ""
    }

    func beginEditing(_ id: String) {
        editingID = id
        editName = load().first(where: { $0.id == id })?.name ?? ""
    }

    func cancelEditing() { editingID = nil }

    func commitRename() {
        guard let id = editingID else { return }
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = load()
        if !name.isEmpty, let index = list.firstIndex(where: { $0.id == id }) {
            list[index].name = name
            save(list)
        }
        editingID = nil
    }

    /// Replaces what a style stores with the settings as they are now.
    func overwriteWithCurrent(_ id: String, _ domain: StyleDomain) {
        var list = load()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].values = snapshot(domain)
        save(list)
        markActive(id, domain)
    }

    func delete(_ id: String, _ domain: StyleDomain) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
        if defaults.string(forKey: activeKey(domain)) == id {
            defaults.removeObject(forKey: activeKey(domain))
            defaults.removeObject(forKey: activeValuesKey(domain))
        }
        if editingID == id { editingID = nil }
    }
}
