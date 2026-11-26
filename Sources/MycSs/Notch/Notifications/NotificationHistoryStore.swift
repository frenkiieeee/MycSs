import Foundation

/// Keeps the notifications the notch has shown between runs, so the "Notificaciones"
/// widget is not empty after a restart (spec 015).
///
/// It is a small JSON file in the app's own folder, readable only by the user. It only
/// holds what already reached the notch (never the whole system database), at most
/// `limit` of them, and it is deleted when the user turns the memory off.
enum NotificationHistoryStore {

    static let limit = 50

    /// A test can point it somewhere else.
    nonisolated(unsafe) static var overrideURL: URL?

    static var url: URL {
        if let overrideURL { return overrideURL }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("MycSs/notification-history.json")
    }

    static func load() -> [NotchNotification] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([NotchNotification].self, from: data)
        else { return [] }
        return Array(items.prefix(limit))
    }

    static func save(_ items: [NotchNotification]) {
        let url = url
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(items.prefix(limit)))
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.warn("notifications: could not save the history: \(error.localizedDescription)")
        }
    }

    static func erase() {
        try? FileManager.default.removeItem(at: url)
    }
}
