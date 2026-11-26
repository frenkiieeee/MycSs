import AppKit
import ApplicationServices
import SQLite3

/// `--banner-probe`: posts a test notification and, for 20 seconds, prints how the
/// system's banners look to Accessibility (roles, subroles and actions), to adjust
/// `SystemBannerCloser` to this version of macOS. Any other notification that shows
/// meanwhile is printed too. It also prints the last records of the database.
///
/// Run it as the app, so it has the app's permissions (Accessibility and Full Disk
/// Access): `open -n -a MycSs.app --stdout /tmp/p.txt --args --banner-probe`. Run from
/// a terminal it gets the terminal's permissions instead.
@MainActor
enum BannerProbe {

    static func run() async {
        print("== banner probe ==")
        print("accessibility trusted: \(AXIsProcessTrusted())")
        let reader = NotificationsModel()
        print("database: \(reader.checkAccess())")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", #"display notification "Prueba de MycSs" with title "MycSs" subtitle "sonda del aviso""#]
        try? process.run()
        process.waitUntilExit()

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            print("no NotificationCenter process")
            return
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var printed = Set<String>()
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            for window in children(root, kAXWindowsAttribute) {
                let title = string(window, kAXTitleAttribute) ?? "?"
                var lines: [String] = []
                dump(window, depth: 0, into: &lines)
                // Widgets are always there: only what is new is printed.
                guard !lines.contains(where: { $0.contains("id=widget-") }) else { continue }
                let key = lines.joined(separator: "\n")
                guard printed.insert(key).inserted else { continue }
                print("-- window '\(title)' --")
                lines.forEach { print($0) }
            }
        }

        let path = NotificationDatabase.candidatePaths()[0]
        var db: OpaquePointer?
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db {
            let newest = NotificationDatabase.maxRecordID(db)
            for record in NotificationDatabase.records(in: db, after: newest - 5) {
                print("record \(record.id) \(record.bundleID) '\(record.title)' \(record.date)")
            }
            sqlite3_close(db)
        }
        print("== done ==")
    }

    private static func dump(_ element: AXUIElement, depth: Int, into lines: inout [String]) {
        guard depth < 12 else { return }
        let indent = String(repeating: "  ", count: depth)
        let role = string(element, kAXRoleAttribute) ?? "?"
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        let identifier = string(element, kAXIdentifierAttribute) ?? ""
        let title = string(element, kAXTitleAttribute) ?? ""
        let description = string(element, kAXDescriptionAttribute) ?? ""
        let value = string(element, kAXValueAttribute).map { String($0.prefix(50)) } ?? ""
        var names: CFArray?
        AXUIElementCopyActionNames(element, &names)
        let actions = (names as? [String] ?? []).map { $0.replacingOccurrences(of: "\n", with: " ") }
        lines.append("\(indent)\(role) [\(subrole)] id=\(identifier) title=\(title) desc=\(description) value=\(value) actions=\(actions)")
        for child in children(element, kAXChildrenAttribute) { dump(child, depth: depth + 1, into: &lines) }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
