import AppKit
import Foundation
import Observation

/// What plays in a tab of a web browser (spec 014, ADR 007).
///
/// A small script (`BrowserMedia.readScript`) runs in the page through AppleScript:
/// `execute javascript` in the Chromium family, `do JavaScript` in Safari. Only the
/// browsers that are open are asked. Every tab is looked at in a **sweep**, at most
/// every few seconds while none is playing; once a tab is found only that one is
/// read, several times a second, like Spotify.
///
/// The sweep can take a while with many tabs, so it never blocks the hub: while
/// one runs, a reading returns the last known state at once.
///
/// Each browser has to allow it: «Allow JavaScript from Apple Events» (Chrome:
/// View > Developer; Safari: Develop, with the developer features on). Without it,
/// the browser answers with an error that is shown in the settings.
///
/// **Firefox, Zen and their kin cannot be scripted**, so they are read from the
/// system's Now Playing instead (`SystemNowPlaying`): title, artist, position and the
/// controls come from there, and the favicon from the browser's session file
/// (`FirefoxSession`). They need no setting in the browser.
final class BrowserSource: PlayerSource {

    let id: NowPlaying.Source = .browser

    struct Browser: Equatable, Identifiable {
        /// The name AppleScript knows it by.
        let name: String
        let bundleID: String
        let isSafari: Bool
        /// Firefox and its derivatives: read from the system's Now Playing.
        var isFirefoxFamily = false
        var id: String { bundleID }
    }

    static let supported: [Browser] = [
        Browser(name: "Google Chrome", bundleID: "com.google.Chrome", isSafari: false),
        Browser(name: "Safari", bundleID: "com.apple.Safari", isSafari: true),
        Browser(name: "Brave Browser", bundleID: "com.brave.Browser", isSafari: false),
        Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isSafari: false),
        Browser(name: "Arc", bundleID: "company.thebrowser.Browser", isSafari: false),
        Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isSafari: false),
        Browser(name: "Chromium", bundleID: "org.chromium.Chromium", isSafari: false),
        Browser(name: "Zen", bundleID: "app.zen-browser.zen", isSafari: false, isFirefoxFamily: true),
        Browser(name: "Firefox", bundleID: "org.mozilla.firefox", isSafari: false, isFirefoxFamily: true),
        Browser(name: "Firefox Developer Edition", bundleID: "org.mozilla.firefoxdeveloperedition", isSafari: false, isFirefoxFamily: true),
        Browser(name: "Floorp", bundleID: "one.ablaze.floorp", isSafari: false, isFirefoxFamily: true),
        Browser(name: "LibreWolf", bundleID: "io.gitlab.librewolf-community", isSafari: false, isFirefoxFamily: true),
        Browser(name: "Waterfox", bundleID: "net.waterfox.waterfox", isSafari: false, isFirefoxFamily: true),
    ]

    /// The tab being followed.
    struct Tab: Equatable {
        let browser: Browser
        /// The window's id, as AppleScript gives it (a number, or text in Arc).
        let window: String
        /// The tab's id (Chromium) or its position in the window (Safari).
        let tab: String
    }

    private let queue = DispatchQueue(label: "com.mycss.browser", qos: .userInitiated)
    private let lock = NSLock()
    private var followed: Tab?
    private var latest: BrowserMedia?
    private var isBusy = false
    private var lastSweep = Date.distantPast
    /// Nothing found in the last sweep: the next one waits longer.
    private var sweepInterval: TimeInterval = 4
    private var iconCache: [String: Data] = [:]

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// Whether the browser is read: «Automático» includes it (on by default) or the user
    /// chose to follow it. Off, no browser is ever asked anything.
    static var isEnabled: Bool {
        AppSettings.shared.browserMedia || AppSettings.shared.playerPreference == .browser
    }

    // MARK: - PlayerSource

    func readPosition(completion: @escaping (PlayerSnapshot) -> Void) {
        let started = Date()
        let open = Self.isEnabled ? Self.openBrowsers() : []
        guard !open.isEmpty else {
            reset()
            SystemNowPlaying.shared.stop()
            completion(Self.snapshot(nil, latency: 0))
            return
        }
        // The system's Now Playing only runs while a browser of the Firefox family is open.
        if open.contains(where: \.isFirefoxFamily) {
            SystemNowPlaying.shared.start()
        } else {
            SystemNowPlaying.shared.stop()
        }
        lock.lock()
        if isBusy {
            // A sweep is running: the last state, without waiting for it.
            let cached = latest
            lock.unlock()
            completion(Self.snapshot(cached, latency: 0))
            return
        }
        isBusy = true
        lock.unlock()

        queue.async { [self] in
            let media = read()
            lock.lock()
            isBusy = false
            lock.unlock()
            completion(Self.snapshot(media, latency: Date().timeIntervalSince(started)))
        }
    }

    func readTrack(completion: @escaping (PlayerTrackMetadata) -> Void) {
        lock.lock()
        let media = latest
        let tab = followed
        lock.unlock()
        let browserName = tab?.browser.name.replacingOccurrences(of: " Browser", with: "") ?? ""
        completion(PlayerTrackMetadata(
            title: media?.title ?? "",
            artist: media.map { $0.artist.isEmpty ? $0.host : $0.artist } ?? "",
            album: media.map { $0.album.isEmpty ? browserName : $0.album } ?? "",
            durationSec: media?.duration ?? 0,
            trackURL: media?.pageURL,
            site: media?.host ?? "",
            appBundleID: tab?.browser.bundleID ?? ""
        ))
    }

    func artworkURL() -> String? { nil }

    /// The page's icon, on a square of its own colour, as the cover.
    func artworkData() -> Data? {
        lock.lock()
        let media = latest
        lock.unlock()
        guard let media else { return nil }
        var icon = downloadIcon(media.iconURL)
        if icon == nil, let bundle = followedBrowser?.bundleID, let app = NotchNotification.icon(for: bundle) {
            // No favicon (a tab too new for the session file): the browser's own icon.
            icon = app.tiffRepresentation
        }
        return BrowserCover.make(icon: icon)
    }

    func send(_ command: PlayerCommand) {
        lock.lock()
        let tab = followed
        lock.unlock()
        guard let tab else { return }
        if tab.browser.isFirefoxFamily {
            SystemNowPlaying.shared.send(command)
            return
        }
        queue.async { [self] in
            _ = run(BrowserMedia.commandScript(command), in: tab)
        }
    }

    /// The browser of the tab being followed, for the badge on the cover.
    var followedBrowser: Browser? {
        lock.lock(); defer { lock.unlock() }
        return followed?.browser
    }

    // MARK: - Reading

    private func reset() {
        lock.lock()
        followed = nil
        latest = nil
        lock.unlock()
    }

    /// On the queue: reads the followed tab, or sweeps when it is time.
    private func read() -> BrowserMedia? {
        lock.lock()
        let tab = followed
        lock.unlock()

        // What a Firefox-family browser plays, from the system.
        let system = readSystem()

        if let current = tab, !current.browser.isFirefoxFamily {
            let answer = run(BrowserMedia.readScript, in: current)
            if let media = answer.flatMap(BrowserMedia.parse) {
                if media.isPlaying {
                    store(media, tab: current)
                    return media
                }
                // Paused: what plays in a Firefox-family browser wins, else another tab may
                // have started meanwhile.
                if let system, system.0.isPlaying {
                    store(system.0, tab: system.1)
                    return system.0
                }
                store(media, tab: current)
                if Date().timeIntervalSince(lastSweep) < 8 { return media }
                if let other = sweep(), other.1 != current {
                    store(other.0, tab: other.1)
                    return other.0
                }
                return media
            }
            // The tab closed, or stopped having media.
            store(nil, tab: nil)
        } else if tab != nil {
            // The tab of a Firefox-family browser: the system's reading, or nothing.
            if let system {
                store(system.0, tab: system.1)
                return system.0
            }
            store(nil, tab: nil)
        }

        if let system, system.0.isPlaying {
            store(system.0, tab: system.1)
            return system.0
        }
        if Date().timeIntervalSince(lastSweep) >= sweepInterval, let (media, found) = sweep() {
            store(media, tab: found)
            return media
        }
        // Nothing plays in a tab we can script; a paused Firefox-family tab still counts.
        if let system {
            store(system.0, tab: system.1)
            return system.0
        }
        return nil
    }

    /// What the system's Now Playing says, when the app that plays is a Firefox-family
    /// browser that is open: as the page's media, with the favicon of its tab.
    private func readSystem() -> (BrowserMedia, Tab)? {
        guard let state = SystemNowPlaying.shared.latest, !state.title.isEmpty,
              let browser = Self.openBrowsers().first(where: { $0.isFirefoxFamily && $0.bundleID == state.bundleID })
        else { return nil }
        BrowserAccess.set(.working, for: browser)

        let page = FirefoxSession.tab(playing: state.title, artist: state.artist, bundleID: state.bundleID)
        let host = page.flatMap { URL(string: $0.url)?.host }.map(BrowserMedia.siteName) ?? ""
        let media = BrowserMedia(
            isPlaying: state.isPlaying,
            position: state.position,
            duration: state.duration,
            title: state.title,
            artist: state.artist,
            album: state.album,
            host: host.isEmpty ? browser.name : host,
            iconURL: page?.icon ?? "",
            pageURL: page?.url ?? ""
        )
        return (media, Tab(browser: browser, window: "", tab: "system"))
    }

    private func store(_ media: BrowserMedia?, tab: Tab?) {
        lock.lock()
        latest = media
        followed = tab
        lock.unlock()
    }

    /// Looks at every tab of every open browser and keeps the one playing (or, if
    /// none plays, one that is paused).
    private func sweep() -> (BrowserMedia, Tab)? {
        lastSweep = Date()
        var paused: (BrowserMedia, Tab)?
        for browser in Self.openBrowsers() where !browser.isFirefoxFamily {
            for (window, tab, text) in sweepResults(browser) {
                guard let media = BrowserMedia.parse(text) else { continue }
                let found = Tab(browser: browser, window: window, tab: tab)
                if media.isPlaying {
                    sweepInterval = 4
                    return (media, found)
                }
                if paused == nil { paused = (media, found) }
            }
        }
        sweepInterval = paused == nil ? 6 : 4
        return paused
    }

    private func sweepResults(_ browser: Browser) -> [(String, String, String)] {
        let literal = BrowserMedia.appleScriptLiteral(BrowserMedia.readScript)
        let source: String
        if browser.isSafari {
            source = """
            tell application "\(browser.name)"
                set found to {}
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if (URL of t as text) starts with "http" then
                            set r to do JavaScript \(literal) in t
                            if r is not missing value and r is not "" then set end of found to {(id of w) as text, i as text, r}
                        end if
                    end repeat
                end repeat
                return found
            end tell
            """
        } else {
            source = """
            tell application "\(browser.name)"
                set found to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t as text) starts with "http" then
                            set r to execute t javascript \(literal)
                            if r is not missing value and r is not "" then set end of found to {(id of w) as text, (id of t) as text, r}
                        end if
                    end repeat
                end repeat
                return found
            end tell
            """
        }
        guard let output = execute(source, browser: browser) else { return [] }
        var result: [(String, String, String)] = []
        for index in stride(from: 1, through: output.numberOfItems, by: 1) {
            guard let item = output.atIndex(index), item.numberOfItems >= 3 else { continue }
            result.append((
                AppleScriptValue.string(item.atIndex(1)),
                AppleScriptValue.string(item.atIndex(2)),
                AppleScriptValue.string(item.atIndex(3))
            ))
        }
        return result
    }

    /// Runs a page script in one tab; nil when the tab or the browser is gone.
    private func run(_ script: String, in tab: Tab) -> String? {
        let literal = BrowserMedia.appleScriptLiteral(script)
        let window = Self.reference(tab.window)
        let source: String
        if tab.browser.isSafari {
            source = """
            tell application "\(tab.browser.name)" to do JavaScript \(literal) in tab \(tab.tab) of window id \(window)
            """
        } else {
            source = """
            tell application "\(tab.browser.name)" to execute (tab id \(Self.reference(tab.tab)) of window id \(window)) javascript \(literal)
            """
        }
        return execute(source, browser: tab.browser)?.stringValue
    }

    /// A number as it is; anything else (Arc's ids) as text.
    private static func reference(_ id: String) -> String {
        Int(id) != nil ? id : BrowserMedia.appleScriptLiteral(id)
    }

    private var compiled: [String: NSAppleScript] = [:]

    private func execute(_ source: String, browser: Browser) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let fresh = NSAppleScript(source: source) else { return nil }
            if compiled.count > 40 { compiled.removeAll() }
            compiled[source] = fresh
            script = fresh
        }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error {
            BrowserAccess.report(error, for: browser)
            return nil
        }
        BrowserAccess.set(.working, for: browser)
        return output
    }

    // MARK: - Icons

    private func downloadIcon(_ urlString: String) -> Data? {
        lock.lock()
        let cached = iconCache[urlString]
        lock.unlock()
        if let cached { return cached }
        // A favicon the session file already holds, as `data:image/png;base64,...`.
        if urlString.hasPrefix("data:") { return Self.decodeDataURL(urlString) }
        guard let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        session.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { result = data }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 7)
        if let result {
            lock.lock()
            if iconCache.count > 30 { iconCache.removeAll() }
            iconCache[urlString] = result
            lock.unlock()
        }
        return result
    }

    // MARK: - Helpers

    /// The bytes of a `data:` URL, in base64 or percent-encoded.
    static func decodeDataURL(_ text: String) -> Data? {
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let header = text[text.startIndex..<comma]
        let body = String(text[text.index(after: comma)...])
        if header.hasSuffix(";base64") { return Data(base64Encoded: body, options: .ignoreUnknownCharacters) }
        return body.removingPercentEncoding.map { Data($0.utf8) }
    }

    static func openBrowsers() -> [Browser] {
        // Asking the system for every running app is not free, and each poll asks more
        // than once. A browser that opens or closes is noticed within two seconds.
        openBrowsersLock.lock()
        defer { openBrowsersLock.unlock() }
        if let cached = openBrowsersCache, Date().timeIntervalSince(cached.date) < 2 {
            return cached.browsers
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let browsers = supported.filter { running.contains($0.bundleID) }
        openBrowsersCache = (Date(), browsers)
        return browsers
    }

    private static let openBrowsersLock = NSLock()
    nonisolated(unsafe) private static var openBrowsersCache: (date: Date, browsers: [Browser])?

    private static func snapshot(_ media: BrowserMedia?, latency: TimeInterval) -> PlayerSnapshot {
        PlayerSnapshot(
            isPlaying: media?.isPlaying ?? false,
            positionSec: media?.position ?? 0,
            title: media?.title ?? "",
            latency: latency,
            takenAt: Date()
        )
    }
}

// MARK: - What each browser allows

/// Whether each browser lets MycSs read its tabs, for the settings.
@MainActor
@Observable
final class BrowserAccess {
    static let shared = BrowserAccess()

    enum State: Equatable {
        case unknown
        case working
        /// «Allow JavaScript from Apple Events» is off in the browser.
        case needsJavaScript
        /// The Automation permission was refused.
        case denied
    }

    private(set) var states: [String: State] = [:]

    func state(_ browser: BrowserSource.Browser) -> State { states[browser.bundleID] ?? .unknown }

    nonisolated static func set(_ state: State, for browser: BrowserSource.Browser) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard shared.states[browser.bundleID] != state else { return }
                shared.states[browser.bundleID] = state
                Log.line("browser: \(browser.name) is \(state)")
            }
        }
    }

    nonisolated static func report(_ error: NSDictionary, for browser: BrowserSource.Browser) {
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
        switch code {
        case -1743: set(.denied, for: browser)
        case -600, -609, -1728, -1719: break   // closed, gone, or a tab that went away
        default:
            if message.localizedCaseInsensitiveContains("JavaScript") {
                set(.needsJavaScript, for: browser)
            } else {
                Log.warn("browser: \(browser.name) error \(code) \(message.prefix(80))")
            }
        }
    }
}
