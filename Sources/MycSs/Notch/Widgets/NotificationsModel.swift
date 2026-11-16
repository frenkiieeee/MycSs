import AppKit
import Observation
import SQLite3

/// One notification of another app, ready to draw.
struct NotchNotification: Identifiable, Equatable {
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
    var appName: String {
        if symbolName != nil { return "MycSs" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// The icon of the app.
    var icon: NSImage? {
        guard symbolName == nil else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The first line that says something: the title, or the body.
    var headline: String { title.isEmpty ? body : title }
    /// What goes under it.
    var detail: String { title.isEmpty ? subtitle : (subtitle.isEmpty ? body : "\(subtitle) · \(body)") }
}

/// Watches the notifications macOS delivers and hands the new ones to the notch.
///
/// **There is no public way to receive another app's notifications**, so this
/// reads the database where Notification Centre keeps them. That folder is
/// protected: the app needs the **Full Disk Access** permission, and without it
/// the notch simply has nothing to show (and says why in the settings).
///
/// **It cannot hide the system's own banner.** macOS draws that by itself and no
/// app can stop it; the settings point to where each app's banner can be turned
/// off, which is the only way to see a notification in one place only.
@MainActor
@Observable
final class NotificationsModel {

    enum Access {
        /// Not looked at yet.
        case unknown
        case granted
        /// The folder exists but the app may not read it: Full Disk Access is missing.
        case denied
        /// There is no database where macOS used to keep it.
        case unavailable
    }

    private(set) var access: Access = .unknown
    /// The newest one, until it is dismissed.
    private(set) var current: NotchNotification?

    /// Called, on the main thread, for every new notification.
    @ObservationIgnored var onNotification: ((NotchNotification) -> Void)?

    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var lastID: Int64 = 0
    @ObservationIgnored private var timer: Timer?
    /// The settings page asks every two seconds with a throwaway model: it should not fill the log.
    @ObservationIgnored var logsChanges = true
    @ObservationIgnored private var lastOpenAttempt = Date.distantPast

    /// Where the database is. A test can point it somewhere else.
    @ObservationIgnored var overridePath: String? = ProcessInfo.processInfo.environment["MYCSS_NOTIFICATION_DB"]

    /// Notifications older than this are history, not news.
    private let freshness: TimeInterval = 90

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let db { sqlite3_close(db) }
        db = nil
        current = nil
    }

    func dismiss() {
        current = nil
    }

    /// Opens the app a notification came from, and dismisses it.
    func open(_ notification: NotchNotification) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notification.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        dismiss()
    }

    /// Looks once whether the database can be read, without starting to watch it.
    /// The settings use it to say whether Full Disk Access is there.
    func checkAccess() -> Access {
        if db == nil { openDatabase() }
        if timer == nil, let db {
            sqlite3_close(db)
            self.db = nil
        }
        return access
    }

    // MARK: - Paths

    /// Where macOS keeps them: a group container since macOS 15, a per-user folder
    /// before that.
    private func candidatePaths() -> [String] {
        if let overridePath { return [overridePath] }
        var paths = [NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buffer = [CChar](repeating: 0, count: 1024)
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            paths.append(String(cString: buffer) + "com.apple.notificationcenter/db2/db")
        }
        return paths
    }

    // MARK: - Polling

    private func poll() {
        if db == nil {
            // Not insisting every second while the permission is missing.
            let wait: TimeInterval = access == .granted ? 1 : 5
            guard Date().timeIntervalSince(lastOpenAttempt) >= wait else { return }
            lastOpenAttempt = Date()
            openDatabase()
        }
        guard let db else { return }

        if lastID == 0 {
            // Start from now: what is already in there is history.
            lastID = Self.maxRecordID(db)
            return
        }

        let fresh = Self.records(in: db, after: lastID)
        guard !fresh.isEmpty else { return }
        lastID = fresh.map(\.id).max() ?? lastID

        for item in fresh where Date().timeIntervalSince(item.date) < freshness {
            guard item.bundleID != Bundle.main.bundleIdentifier else { continue }
            guard !item.headline.isEmpty else { continue }
            current = item
            onNotification?(item)
        }
    }

    private func openDatabase() {
        var foundFile = false
        for path in candidatePaths() {
            // Even asking whether the file exists can be refused.
            var handle: OpaquePointer?
            let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
            if result == SQLITE_OK, let handle {
                // A real read, to be sure it is allowed.
                var statement: OpaquePointer?
                if sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM record", -1, &statement, nil) == SQLITE_OK {
                    sqlite3_finalize(statement)
                    db = handle
                    if access != .granted, logsChanges { Log.line("notifications: reading \(path)") }
                    access = .granted
                    return
                }
                sqlite3_finalize(statement)
                sqlite3_close(handle)
                foundFile = true
                continue
            }
            if let handle { sqlite3_close(handle) }
            // "Operation not permitted" / "unable to open": the folder is there but
            // closed to this app. Nothing at all means there is no such folder.
            let folder = (path as NSString).deletingLastPathComponent
            let folderExists = (try? FileManager.default.contentsOfDirectory(atPath: folder)) != nil
            if folderExists || FileManager.default.fileExists(atPath: path) { foundFile = true }
            if !foundFile, access == .unknown {
                // The folder cannot even be listed: the usual sign of a missing permission.
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue {
                    foundFile = true
                }
            }
        }
        let newAccess: Access = foundFile ? .denied : .unavailable
        if access != newAccess {
            access = newAccess
            if logsChanges { Log.line("notifications: \(newAccess == .denied ? "Full Disk Access is missing" : "no database found")") }
        }
    }

    // MARK: - Reading the database

    private static func maxRecordID(_ db: OpaquePointer) -> Int64 {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(rec_id), 1) FROM record", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else { return 1 }
        return max(sqlite3_column_int64(statement, 0), 1)
    }

    /// The records after `id`, oldest first.
    static func records(in db: OpaquePointer, after id: Int64) -> [NotchNotification] {
        let sql = """
        SELECT r.rec_id, a.identifier, r.data, r.delivered_date
        FROM record r LEFT JOIN app a ON r.app_id = a.app_id
        WHERE r.rec_id > ? ORDER BY r.rec_id ASC LIMIT 20
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int64(statement, 1, id)

        var result: [NotchNotification] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let recID = sqlite3_column_int64(statement, 0)
            let identifier = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            var delivered = sqlite3_column_double(statement, 3)
            // Seconds since 2001, like every Cocoa date; a missing one means "now".
            if delivered <= 0 { delivered = Date().timeIntervalSinceReferenceDate }

            guard let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }

            let request = plist["req"] as? [String: Any] ?? [:]
            let bundle = identifier.isEmpty ? (plist["app"] as? String ?? "") : identifier
            result.append(NotchNotification(
                id: recID,
                bundleID: bundle,
                title: request["titl"] as? String ?? "",
                subtitle: request["subt"] as? String ?? "",
                body: request["body"] as? String ?? "",
                date: Date(timeIntervalSinceReferenceDate: delivered)
            ))
        }
        return result
    }
}
