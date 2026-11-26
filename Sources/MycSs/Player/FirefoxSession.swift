import Foundation

/// The tabs Firefox and its derivatives (Zen, Floorp, LibreWolf, Waterfox) keep in
/// their session file, to give the page that plays a favicon (spec 014).
///
/// Those browsers cannot be scripted, so the system's Now Playing says the title of
/// what plays but not which page it is. Their session file (`recovery.jsonlz4`,
/// written every few seconds) lists every tab with its URL, its title and its
/// favicon, so the tab is found by its title and the icon is already there, with no
/// request to any site. If the file cannot be read, or the tab is too new to be in
/// it, the cover is the browser's own icon.
enum FirefoxSession {

    struct Tab: Equatable {
        let url: String
        let title: String
        /// A `data:` or `https:` URL, when the tab has a favicon.
        let icon: String
        let lastAccessed: Double
    }

    /// The bundle identifiers of the browsers of this family, and the folder each one
    /// keeps its profiles in, under `~/Library/Application Support`.
    static let browsers: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "app.zen-browser.zen": "zen",
        "one.ablaze.floorp": "Floorp",
        "io.gitlab.librewolf-community": "LibreWolf",
        "net.waterfox.waterfox": "Waterfox",
    ]

    static func isFirefoxFamily(_ bundleID: String) -> Bool { browsers[bundleID] != nil }

    // MARK: - Finding a tab

    private static let lock = NSLock()
    private static var cache: [String: (modified: Date, tabs: [Tab])] = [:]

    /// The tab that plays `title` (and, when the page says it, `artist`).
    static func tab(playing title: String, artist: String = "", bundleID: String) -> Tab? {
        guard let folder = browsers[bundleID] else { return nil }
        let tabs = tabs(inFolder: folder)
        return match(tabs, title: title, artist: artist)
    }

    /// The tabs of a browser's latest session, for the self test.
    static func allTabs(bundleID: String) -> [Tab] {
        browsers[bundleID].map(tabs(inFolder:)) ?? []
    }

    /// The best tab for a title: its own title is the page's, which often adds the
    /// site ("Song - YouTube") or a counter ("(3) Song"), so it is compared without them.
    static func match(_ tabs: [Tab], title: String, artist: String = "") -> Tab? {
        let wanted = normalise(title)
        guard wanted.count >= 3 else { return nil }
        var best: (score: Int, tab: Tab)?
        for tab in tabs where !tab.url.hasPrefix("about:") {
            let have = normalise(tab.title)
            guard !have.isEmpty else { continue }
            var score = 0
            if have == wanted { score = 100 }
            else if have.contains(wanted) { score = 80 - min(have.count - wanted.count, 40) }
            else if wanted.contains(have), have.count >= 6 { score = 60 }
            guard score > 0 else { continue }
            if !artist.isEmpty, have.contains(normalise(artist)) { score += 5 }
            if score > (best?.score ?? 0)
                || (score == best?.score && tab.lastAccessed > (best?.tab.lastAccessed ?? 0)) {
                best = (score, tab)
            }
        }
        return best?.tab
    }

    /// Lower case, without the counter some sites put first ("(8606) ") and without accents.
    static func normalise(_ text: String) -> String {
        var result = text
        if result.hasPrefix("("), let close = result.firstIndex(of: ")"),
           result[result.index(after: result.startIndex)..<close].allSatisfy(\.isNumber) {
            result = String(result[result.index(after: close)...])
        }
        return result.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The files

    /// The tabs of the most recently written session of a browser's profiles.
    private static func tabs(inFolder folder: String) -> [Tab] {
        let manager = FileManager.default
        let profiles = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(folder)/Profiles", isDirectory: true)
        guard let names = try? manager.contentsOfDirectory(atPath: profiles.path) else { return [] }
        var newest: (date: Date, file: URL)?
        for name in names {
            let file = profiles.appendingPathComponent(name).appendingPathComponent("sessionstore-backups/recovery.jsonlz4")
            guard let date = (try? manager.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date else { continue }
            if date > (newest?.date ?? .distantPast) { newest = (date, file) }
        }
        guard let newest else { return [] }

        lock.lock()
        if let cached = cache[newest.file.path], cached.modified == newest.date {
            lock.unlock()
            return cached.tabs
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: newest.file), let tabs = tabs(from: data) else { return [] }
        lock.lock()
        cache = [newest.file.path: (newest.date, tabs)]
        lock.unlock()
        return tabs
    }

    /// The tabs of the contents of a `recovery.jsonlz4`.
    static func tabs(from file: Data) -> [Tab]? {
        guard let json = decompress(file),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]]
        else { return nil }
        var result: [Tab] = []
        for window in windows {
            for tab in window["tabs"] as? [[String: Any]] ?? [] {
                let entries = tab["entries"] as? [[String: Any]] ?? []
                let index = (tab["index"] as? Int ?? entries.count) - 1
                guard entries.indices.contains(index) else { continue }
                let entry = entries[index]
                result.append(Tab(
                    url: entry["url"] as? String ?? "",
                    title: entry["title"] as? String ?? "",
                    icon: tab["image"] as? String ?? "",
                    lastAccessed: (tab["lastAccessed"] as? NSNumber)?.doubleValue ?? 0
                ))
            }
        }
        return result
    }

    // MARK: - mozlz4

    /// Firefox's own file format: `mozLz40\0`, the size (4 bytes, little endian) and one
    /// LZ4 block.
    static func decompress(_ file: Data) -> Data? {
        let magic = Array("mozLz40\0".utf8)
        guard file.count > 12, Array(file.prefix(8)) == magic else { return nil }
        let bytes = [UInt8](file)
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size >= 0, size < 256_000_000 else { return nil }
        return lz4Block(Array(bytes[12...]), size: size).map { Data($0) }
    }

    /// An LZ4 block: sequences of literals and back references.
    static func lz4Block(_ source: [UInt8], size: Int) -> [UInt8]? {
        var output = [UInt8]()
        output.reserveCapacity(size)
        var position = 0
        let end = source.count
        while position < end {
            let token = Int(source[position]); position += 1
            var literals = token >> 4
            if literals == 15 {
                while position < end {
                    let extra = Int(source[position]); position += 1
                    literals += extra
                    if extra != 255 { break }
                }
            }
            guard position + literals <= end else { return nil }
            output.append(contentsOf: source[position..<position + literals])
            position += literals
            if position >= end { break }   // the last sequence has no match

            guard position + 2 <= end else { return nil }
            let offset = Int(source[position]) | Int(source[position + 1]) << 8
            position += 2
            guard offset > 0, offset <= output.count else { return nil }
            var length = token & 15
            if length == 15 {
                while position < end {
                    let extra = Int(source[position]); position += 1
                    length += extra
                    if extra != 255 { break }
                }
            }
            length += 4
            guard output.count + length <= size + 4 else { return nil }
            var from = output.count - offset
            for _ in 0..<length {
                output.append(output[from])
                from += 1
            }
        }
        return output.count == size ? output : nil
    }

    /// The reverse, for the tests: an LZ4 block made only of literals is valid.
    static func compressForTest(_ json: Data) -> Data {
        var block = [UInt8]()
        let count = json.count
        if count < 15 {
            block.append(UInt8(count << 4))
        } else {
            block.append(0xF0)
            var rest = count - 15
            while rest >= 255 { block.append(255); rest -= 255 }
            block.append(UInt8(rest))
        }
        block.append(contentsOf: json)
        var file = Data("mozLz40\0".utf8)
        for shift in stride(from: 0, to: 32, by: 8) { file.append(UInt8((count >> shift) & 0xFF)) }
        file.append(contentsOf: block)
        return file
    }
}
