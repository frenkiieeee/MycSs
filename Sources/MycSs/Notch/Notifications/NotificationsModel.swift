import AppKit
import Observation
import SQLite3

/// Watches the notifications macOS delivers and hands the new ones to the notch
/// (specs 006 and 012).
///
/// **There is no public way to receive another app's notifications**, so this
/// reads the database where Notification Centre keeps them (`NotificationDatabase`).
/// That folder is protected: the app needs the **Full Disk Access** permission, and
/// without it the notch simply has nothing to show (and says why in the settings).
///
/// **It reads when the database is written**, not on a clock: `FileWatcher` hears
/// the write as it happens, so a notification reaches the notch a few milliseconds
/// after macOS stores it. A slow timer stays as a safety net.
///
/// Each app has a rule (`AppSettings.NotificationRule`): in the notch and the system,
/// the notch only (the system's banner is then closed, see `SystemBannerCloser`), or
/// the system only (MycSs ignores it). The last ones that reached the notch are kept
/// in memory, for the notch's widget.
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
    /// The last ones that reached the notch, newest first.
    private(set) var history: [NotchNotification] = []

    /// Called, on the main thread, for every new notification the notch shows.
    @ObservationIgnored var onNotification: ((NotchNotification) -> Void)?

    @ObservationIgnored private var db: OpaquePointer?
    @ObservationIgnored private var lastID: Int64 = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private let watcher = FileWatcher()
    @ObservationIgnored let banners = SystemBannerCloser()
    /// The settings page asks every two seconds with a throwaway model: it should not fill the log.
    @ObservationIgnored var logsChanges = true
    @ObservationIgnored private var lastOpenAttempt = Date.distantPast
    @ObservationIgnored private var openPath: String?

    /// Where the database is. A test can point it somewhere else.
    @ObservationIgnored var overridePath: String? = ProcessInfo.processInfo.environment["MYCSS_NOTIFICATION_DB"]

    init(demo: Bool = false) {
        guard demo else { return }
        // The settings previews and the pictures show a history of their own.
        history = [
            NotchNotification(id: 3, bundleID: "com.apple.MobileSMS", title: "Marta", subtitle: "",
                              body: "¿Comemos hoy?", date: Date().addingTimeInterval(-120)),
            NotchNotification(id: 2, bundleID: "com.apple.mail", title: "Factura de noviembre", subtitle: "",
                              body: "Adjunto el PDF", date: Date().addingTimeInterval(-1500)),
            NotchNotification(id: 1, bundleID: "com.apple.iCal", title: "Examen a las 13:25", subtitle: "",
                              body: "En 1 hora", date: Date().addingTimeInterval(-3600)),
        ]
    }

    /// Notifications older than this are history, not news.
    private let freshness: TimeInterval = 90
    /// A notification left alone this long is taken as seen (spec 018).
    static let lifetime: TimeInterval = 24 * 3600
    private let historyLimit = 30
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// Writes the history shortly after the last change (several can come in a row).
    private func scheduleSave() {
        // A test database or a throwaway model never touches the real history file.
        guard logsChanges, overridePath == nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            if AppSettings.shared.notchNotificationKeepHistory {
                NotificationHistoryStore.save(self.history)
            } else {
                NotificationHistoryStore.erase()
            }
        }
    }

    // MARK: - Lifecycle

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        if history.isEmpty, overridePath == nil, AppSettings.shared.notchNotificationKeepHistory {
            history = NotificationHistoryStore.load()
        }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // An app that comes to the front has been looked at (spec 018). A test database
        // never listens: the apps of the person running it are not part of the test.
        if overridePath == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier ?? ""
                MainActor.assumeIsolated { self?.appActivated(bundleID) }
            }
        }
        watcher.onChange = { [weak self] in self?.poll() }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        watcher.stop()
        banners.stop()
        if let db { sqlite3_close(db) }
        db = nil
        openPath = nil
        current = nil
    }

    func dismiss() {
        current = nil
    }

    func clearHistory() {
        history.removeAll()
        scheduleSave()
    }

    func remove(_ notification: NotchNotification) {
        history.removeAll { $0.id == notification.id }
        if hoveredID == notification.id { hoveredID = nil }
        scheduleSave()
    }

    /// The row under the pointer, which shows its own cross instead of the time.
    private(set) var hoveredID: Int64?

    func hover(_ notification: NotchNotification, _ inside: Bool) {
        if inside { hoveredID = notification.id } else if hoveredID == notification.id { hoveredID = nil }
    }

    // MARK: - Seen elsewhere (spec 018)

    /// An app came to the front: what it had told the user is taken as seen.
    func appActivated(_ bundleID: String) {
        guard !bundleID.isEmpty, bundleID != Bundle.main.bundleIdentifier else { return }
        let before = history.count
        history.removeAll { $0.bundleID == bundleID && $0.symbolName == nil }
        if current?.bundleID == bundleID { dismiss() }
        if history.count != before { scheduleSave() }
    }

    /// Takes out what is too old, and what is no longer in the Notification Centre: it
    /// was dismissed there, its banner was clicked, or the app withdrew it once the
    /// message was read. A failed read of the database removes nothing.
    func prune(database db: OpaquePointer?) {
        var kept = history
        let limit = Date().addingTimeInterval(-Self.lifetime)
        kept.removeAll { $0.date < limit }

        if let db {
            // Where MycSs closes the system's banner itself, the record can vanish with
            // it, so its absence says nothing about whether it was seen.
            let settings = AppSettings.shared
            let checkable = kept.filter { $0.symbolName == nil && !settings.notificationRule(for: $0.bundleID).hidesBanner }
            if let alive = NotificationDatabase.existing(checkable.map(\.id), in: db) {
                let gone = Set(checkable.map(\.id)).subtracting(alive)
                if !gone.isEmpty {
                    kept.removeAll { gone.contains($0.id) }
                    if logsChanges { Log.line("notifications: \(gone.count) seen elsewhere, taken out of the list") }
                }
            }
        }
        guard kept.count != history.count else { return }
        history = kept
        scheduleSave()
    }

    /// Opens the app a notification came from. Once opened it is dealt with, so it
    /// leaves the history as well as the notch.
    func open(_ notification: NotchNotification) {
        remove(notification)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notification.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        if current?.id == notification.id { dismiss() }
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

    /// The apps that sent notifications (from the database and the history), the
    /// most recent first, for the settings.
    func knownApps() -> [String] {
        if db == nil { openDatabase() }
        var apps = history.map(\.bundleID)
        if let db { apps += NotificationDatabase.apps(in: db) }
        if timer == nil, let db {
            sqlite3_close(db)
            self.db = nil
        }
        var seen = Set<String>()
        let own = Bundle.main.bundleIdentifier ?? ""
        return apps.filter { !$0.isEmpty && $0 != own && seen.insert($0).inserted }
    }

    // MARK: - Reading

    private func candidatePaths() -> [String] {
        if let overridePath { return [overridePath] }
        return NotificationDatabase.candidatePaths()
    }

    func poll() {
        if db == nil {
            // Not insisting every time while the permission is missing.
            let wait: TimeInterval = access == .granted ? 1 : 5
            guard Date().timeIntervalSince(lastOpenAttempt) >= wait else { return }
            lastOpenAttempt = Date()
            openDatabase()
        }
        guard let db else { return }

        // What was seen somewhere else leaves the list (spec 018).
        prune(database: db)

        if lastID == 0 {
            // Start from now: what is already in there is history.
            lastID = NotificationDatabase.maxRecordID(db)
            return
        }

        let fresh = NotificationDatabase.records(in: db, after: lastID)
        guard !fresh.isEmpty else { return }
        lastID = fresh.map(\.id).max() ?? lastID

        let settings = AppSettings.shared
        for item in fresh where Date().timeIntervalSince(item.date) < freshness {
            guard item.bundleID != Bundle.main.bundleIdentifier, !item.headline.isEmpty else { continue }
            let rule = settings.notificationRule(for: item.bundleID)
            guard rule.shownInNotch else { continue }
            history.removeAll { $0.id == item.id }
            history.insert(item, at: 0)
            scheduleSave()
            if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
            current = item
            onNotification?(item)
            if rule.hidesBanner, isRunning, overridePath == nil { banners.close(matching: item) }
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
                    if timer != nil, openPath != path {
                        openPath = path
                        // The database, its write-ahead log and the folder (where the log appears).
                        let folder = (path as NSString).deletingLastPathComponent
                        watcher.watch([path, path + "-wal", folder])
                    }
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
}
