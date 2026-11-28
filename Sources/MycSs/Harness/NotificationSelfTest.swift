import Foundation
import SQLite3

/// Proves the notification reader against a database built here, with the same
/// tables macOS uses. The real one is closed to this app without Full Disk
/// Access, so this is what can be checked without it.
enum NotificationSelfTest {

    @MainActor
    static func run() async {
        print("== Notification reader self test ==")
        let path = NSTemporaryDirectory() + "mycss-notifications-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }

        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            if !passed { failures += 1 }
            print("  \(passed ? "OK  " : "FAIL") \(name)")
        }

        // The database: the tables macOS has, with one old notification in it.
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            print("  FAIL could not create the test database")
            return
        }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT);
        CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, uuid BLOB, data BLOB,
            request_date REAL, request_last_date REAL, delivered_date REAL, presented INTEGER,
            style INTEGER, snooze_fire_date REAL);
        INSERT INTO app VALUES (1, 'com.apple.MobileSMS');
        INSERT INTO app VALUES (2, 'com.apple.mail');
        """
        check("schema created", sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)

        func insert(id: Int, app: Int, title: String, subtitle: String, body: String, age: TimeInterval) {
            let plist: [String: Any] = ["app": "x", "req": ["titl": title, "subt": subtitle, "body": body]]
            let data = (try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)) ?? Data()
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO record (rec_id, app_id, data, delivered_date) VALUES (?, ?, ?, ?)", -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(id))
            sqlite3_bind_int(statement, 2, Int32(app))
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), nil) }
            sqlite3_bind_double(statement, 4, Date().addingTimeInterval(-age).timeIntervalSinceReferenceDate)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        insert(id: 5, app: 1, title: "Old news", subtitle: "", body: "Already there", age: 3600)

        let model = NotificationsModel()
        model.overridePath = path
        var received: [NotchNotification] = []
        model.onNotification = { received.append($0) }
        model.start()
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        check("the database is readable", model.access == .granted)
        check("what was already there is not announced", received.isEmpty)

        // New ones arrive. The safety timer runs every 3 s: arriving well before that
        // means the write itself was heard (spec 012).
        let rules = UserDefaults.standard.object(forKey: SettingKey.notchNotificationRules)
        let defaultRule = UserDefaults.standard.object(forKey: SettingKey.notchNotificationDefault)
        defer {
            UserDefaults.standard.set(rules, forKey: SettingKey.notchNotificationRules)
            UserDefaults.standard.set(defaultRule, forKey: SettingKey.notchNotificationDefault)
        }
        UserDefaults.standard.removeObject(forKey: SettingKey.notchNotificationRules)
        UserDefaults.standard.removeObject(forKey: SettingKey.notchNotificationDefault)
        try? await Task.sleep(nanoseconds: 3_200_000_000)
        let sent = Date()
        insert(id: 6, app: 1, title: "Marta", subtitle: "", body: "¿Comemos hoy?", age: 1)
        insert(id: 7, app: 2, title: "Factura", subtitle: "Proveedor", body: "Adjunto el PDF", age: 2)
        for _ in 0..<40 where received.count < 2 { try? await Task.sleep(nanoseconds: 25_000_000) }
        let delay = Date().timeIntervalSince(sent)
        check(String(format: "two new notifications arrive at once (%.0f ms, the timer would take up to 3 s)", delay * 1000),
              received.count == 2 && delay < 0.8)
        check("title, body and app are read",
              received.first.map { $0.title == "Marta" && $0.body == "¿Comemos hoy?" && $0.bundleID == "com.apple.MobileSMS" } ?? false)
        check("subtitle is read", received.last?.subtitle == "Proveedor")
        check("the newest one is the current one", model.current?.title == "Factura")
        check("the headline and the detail", model.current?.headline == "Factura" && model.current?.detail == "Proveedor · Adjunto el PDF")

        // A stale one (an hour old) is history.
        insert(id: 8, app: 1, title: "Ayer", subtitle: "", body: "old", age: 3600)
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        check("an old notification is not announced", received.count == 2)

        // An app set to "only the system" stays out of the notch.
        AppSettings.shared.setNotificationRule(.system, for: "com.apple.MobileSMS")
        insert(id: 9, app: 1, title: "Marta", subtitle: "", body: "Otra", age: 1)
        try? await Task.sleep(nanoseconds: 600_000_000)
        check("an app set to «Solo sistema» is not announced", received.count == 2)
        check("the history keeps what reached the notch, newest first",
              model.history.map(\.id) == [7, 6])

        // Seen somewhere else (spec 018): dismissed in the Notification Centre, or its app
        // brought to the front. Neither touches the database from here.
        sqlite3_exec(db, "DELETE FROM record WHERE rec_id = 6", nil, nil, nil)
        for _ in 0..<60 where model.history.count > 1 { try? await Task.sleep(nanoseconds: 25_000_000) }
        check("one dismissed in the Notification Centre leaves the list", model.history.map(\.id) == [7])
        check("the others stay", model.history.count == 1)
        model.appActivated("com.apple.mail")
        check("coming to the app of a notification takes it out", model.history.isEmpty)
        check("and the one on the notch goes too", model.current == nil)

        // Dismissed.
        model.dismiss()
        check("dismissing clears it", model.current == nil)
        model.clearHistory()
        check("the history can be cleared", model.history.isEmpty)
        model.stop()

        // A folder the app cannot read.
        let closed = NotificationsModel()
        closed.overridePath = "/System/Library/CoreServices/definitely-not-a-database/db"
        closed.start()
        try? await Task.sleep(nanoseconds: 300_000_000)
        check("a missing database is reported, not a crash", closed.access == .unavailable || closed.access == .denied)
        closed.stop()

        // The real database, only to say how it looks from here. Nothing is read
        // from it but whether it can be opened.
        let real = NotificationsModel()
        real.overridePath = nil
        real.start()
        try? await Task.sleep(nanoseconds: 400_000_000)
        print("  (information) the real notification database: \(real.access)")
        real.stop()

        print(failures == 0 ? "== all passed ==" : "== \(failures) FAILED ==")
    }
}
