import AppKit

/// One notification of another app, ready to draw.
struct NotchNotification: Identifiable, Equatable, Codable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    /// An SF Symbol to use instead of an app icon, for what MycSs says itself
    /// (the timer ending).
    var symbolName: String? = nil

    /// The name of the app, from its bundle.
    var appName: String { Self.appName(for: bundleID, isOwn: symbolName != nil) }

    /// The icon of the app.
    var icon: NSImage? {
        guard symbolName == nil else { return nil }
        return Self.icon(for: bundleID)
    }

    /// The first line that says something: the title, or the body.
    var headline: String { title.isEmpty ? body : title }
    /// What goes under it.
    var detail: String { title.isEmpty ? subtitle : (subtitle.isEmpty ? body : "\(subtitle) · \(body)") }

    /// What the notch writes: with «Mostrar el contenido» off, only who and that
    /// something arrived (MycSs's own, like the timer, always say what they are).
    var shownHeadline: String {
        symbolName != nil || AppSettings.shared.notchNotificationShowBody ? headline : appName
    }
    var shownDetail: String {
        symbolName != nil || AppSettings.shared.notchNotificationShowBody ? detail : "Nueva notificación"
    }

    // MARK: - Apps

    /// Apps are asked once: the widget and the notch draw many times a second.
    private static let cacheLock = NSLock()
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage?] = [:]

    static func appName(for bundleID: String, isOwn: Bool = false) -> String {
        if isOwn { return "MycSs" }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let known = names[bundleID] { return known }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            name = bundleID
        }
        names[bundleID] = name
        return name
    }

    static func icon(for bundleID: String) -> NSImage? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let known = icons[bundleID] { return known }
        var icon: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        icons[bundleID] = icon
        return icon
    }
}
