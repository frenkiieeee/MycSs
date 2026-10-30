import Foundation

/// Minimal file logger. Everything the app does that is worth debugging goes
/// through here: lock state transitions, SkyLight symbol resolution, lyrics
/// fetching, and sync timing.
///
/// Writes to `~/Library/Logs/MycSs.log`. Log lines are cheap and the file is
/// truncated on launch so a long-running session cannot grow without bound.
enum Log {
    private static let url: URL = {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("MycSs.log")
    }()

    /// Set `MYCSS_LOG` to a path to override the log location (used by the
    /// spike scripts to capture output without touching the user's real log).
    static var overridePath: String? = ProcessInfo.processInfo.environment["MYCSS_LOG"]

    private static let queue = DispatchQueue(label: "com.mycss.log")

    /// `2026-10-24 18:42:07.123`
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// The open handle of the log file.
    ///
    /// The file is opened once and kept open: opening, writing and closing it
    /// for every line costs three system calls, and the app logs often enough
    /// (every lock, every track change) for that to show up.
    private static var handle: FileHandle?

    static func line(_ message: String) {
        // Local time with sub-second precision: the log is read by a human
        // comparing it against what they just did on screen.
        let stamp = Self.stampFormatter.string(from: Date())
        let text = "\(stamp) \(message)\n"
        queue.async {
            let destination = overridePath.map { URL(fileURLWithPath: $0) } ?? url
            guard let data = text.data(using: .utf8) else { return }

            if handle == nil {
                if !FileManager.default.fileExists(atPath: destination.path) {
                    FileManager.default.createFile(atPath: destination.path, contents: nil)
                }
                handle = try? FileHandle(forWritingTo: destination)
            }

            guard let handle else {
                try? text.write(to: destination, atomically: true, encoding: .utf8)
                return
            }
            handle.seekToEndOfFile()
            handle.write(data)
        }
    }

    /// Emphasises a line in the log so the important events are easy to grep.
    static func warn(_ message: String) {
        line("WARN  \(message)")
    }

    static func error(_ message: String) {
        line("ERROR \(message)")
    }
}
