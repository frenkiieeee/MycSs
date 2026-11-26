import Foundation
import SQLite3

/// The queries on the database where Notification Centre keeps the notifications
/// (`usernoted`). Read only; see `NotificationsModel` for why it is read at all.
enum NotificationDatabase {

    /// Where macOS keeps it: a group container since macOS 15, a per-user folder
    /// before that.
    static func candidatePaths() -> [String] {
        var paths = [NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buffer = [CChar](repeating: 0, count: 1024)
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            paths.append(String(cString: buffer) + "com.apple.notificationcenter/db2/db")
        }
        return paths
    }

    static func maxRecordID(_ db: OpaquePointer) -> Int64 {
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

    /// The apps that have notifications in the database, the most recent first.
    /// The settings list them so a rule can be chosen for each.
    static func apps(in db: OpaquePointer, limit: Int = 40) -> [String] {
        let sql = """
        SELECT a.identifier, MAX(r.rec_id) AS newest FROM record r JOIN app a ON r.app_id = a.app_id
        WHERE a.identifier IS NOT NULL GROUP BY a.identifier ORDER BY newest DESC LIMIT ?
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_int(statement, 1, Int32(limit))
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
        return result
    }
}
