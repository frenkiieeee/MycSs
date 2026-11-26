import AppKit
import JavaScriptCore

/// Checks of specs 012, 013 and 014 that need no player, permission or network:
/// the drag of files, the notification rules and the banner matching, the stale
/// cover URL, the order of the players, and the browser's page scripts, which run
/// here in JavaScriptCore against a page made of stubs.
extension SelfTest {

    private static func report(_ ok: Bool, _ what: String) {
        print(ok ? "  OK: \(what)" : "  !! FAIL: \(what)")
    }

    @MainActor
    static func testBehaviour() async {
        testDragTracker()
        testNotificationRules()
        await testStaleCover()
        testPlayerOrder()
        testBrowserScripts()
        testFirefoxFamily()
    }

    // MARK: - Spec 013

    @MainActor
    private static func testDragTracker() {
        print("\n-- Dragging files (spec 013) --")
        var count = 10
        var down = false
        var files = true
        let tracker = DragTracker()
        tracker.pasteboardCount = { count }
        tracker.buttonDown = { down }
        tracker.hasFiles = { files }

        // An old drag left files on the pasteboard; a click and hold is not a drag.
        down = true
        tracker.pressed()
        report(!tracker.update(), "a click and hold with old files on the pasteboard is not a drag")
        // The drag writes the pasteboard after the press.
        count += 1
        report(tracker.update(), "files written after the press are a drag")
        down = false
        report(!tracker.update(), "letting go ends it")
        // A press the monitor missed: the first tick notes the pasteboard as old.
        down = true
        report(!tracker.update(), "a missed press still does not take old files for a drag")
        count += 1
        files = false
        report(!tracker.update(), "a drag of something that is not files does not count")
        down = false
        tracker.update()
    }

    // MARK: - Spec 012

    @MainActor
    private static func testNotificationRules() {
        print("\n-- Notification rules (spec 012) --")
        let settings = AppSettings.shared
        let keys = [SettingKey.notchNotificationRules, SettingKey.notchNotificationDefault]
        let stored = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in stored {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        UserDefaults.standard.removeObject(forKey: SettingKey.notchNotificationRules)
        settings.notchNotificationDefault = .both
        report(settings.notificationRule(for: "com.test.app") == .both, "an app without a rule follows the default")
        settings.setNotificationRule(.notch, for: "com.test.app")
        report(settings.notificationRule(for: "com.test.app") == .notch, "an app keeps its own rule")
        settings.notchNotificationDefault = .system
        report(settings.notificationRule(for: "com.test.app") == .notch && settings.notificationRule(for: "com.other") == .system,
               "changing the default moves only the apps without a rule")
        settings.setNotificationRule(.system, for: "com.test.app")
        report(settings.notchNotificationRules["com.test.app"] == nil, "a rule equal to the default is not stored")

        let message = NotchNotification(id: 1, bundleID: "net.whatsapp.WhatsApp", title: "Marta", subtitle: "", body: "¿Comemos hoy?", date: Date())
        report(SystemBannerCloser.matches(message, text: "whatsapp marta ¿comemos hoy? now"), "a banner with the notification's text is its banner")
        report(!SystemBannerCloser.matches(message, text: "mail factura adjunto"), "another banner is left alone")
        report(SystemBannerCloser.isClose("Name:Cerrar\nTarget:0x0", description: "")
               && SystemBannerCloser.isClose("AXPress", description: "Close")
               && !SystemBannerCloser.isClose("AXPress", description: "Show Details"),
               "the close action is told apart in Spanish and English")

        // Several in a row from one app are counted.
        let notch = NotchModel()
        notch.showNotification(message, for: 30)
        notch.showNotification(NotchNotification(id: 2, bundleID: message.bundleID, title: "Marta", subtitle: "", body: "¿Sí?", date: Date()), for: 30)
        let counted = notch.notificationCount == 2
        notch.showNotification(NotchNotification(id: 3, bundleID: "com.apple.mail", title: "Factura", subtitle: "", body: "", date: Date()), for: 30)
        report(counted && notch.notificationCount == 1, "several from one app are counted, another app starts again")
        notch.reset()
    }

    // MARK: - The cover of Spotify's DJ

    private static func testStaleCover() async {
        print("\n-- Stale cover URL --")
        let cover = CoverProvider.shared
        await cover.remember(url: "https://i.scdn.co/image/old", for: "song a|singer a|")
        let staleWithoutPrevious = await cover.isStale("https://i.scdn.co/image/old", for: "song b|singer b|", previousURL: nil)
        let ownIsFine = await cover.isStale("https://i.scdn.co/image/old", for: "song a|singer a|", previousURL: nil)
        let newIsFine = await cover.isStale("https://i.scdn.co/image/new", for: "song b|singer b|", previousURL: nil)
        report(staleWithoutPrevious, "a URL seen with another song is stale even when the previous one came from the cache")
        report(!ownIsFine && !newIsFine, "a song's own URL and a new one are used")

        // Spotify's DJ talking: every segment is "Up next" by the DJ, with its own item.
        var dj = NowPlaying(source: .spotify, title: "Up next", artist: "DJ Fabi", album: "DJ")
        dj.spotifyURL = "spotify:media:2hK3et05oRbVrFbgvJlrh2"
        var other = dj
        other.spotifyURL = "spotify:media:7Xyz"
        var song = NowPlaying(source: .spotify, title: "Song", artist: "Singer", album: "Album")
        song.spotifyURL = "spotify:track:abc"
        report(dj.isSpotifyNonSong && !song.isSpotifyNonSong, "a DJ segment is told from a song")
        report(dj.coverKey != other.coverKey && song.coverKey == song.trackKey,
               "each DJ segment has its own cover key, a song keeps its own")
        report(dj.coverFromPlayerOnly && !song.coverFromPlayerOnly, "a DJ segment is never searched in the catalogues")
    }

    // MARK: - Spec 014

    private static func testPlayerOrder() {
        print("\n-- Moving between players (spec 014) --")
        report(PlayerHub.next(after: .spotify, in: [.spotify, .browser]) == .browser, "from Spotify to the browser")
        report(PlayerHub.next(after: .browser, in: [.spotify, .appleMusic, .browser]) == .spotify, "from the browser round to Spotify")
        report(PlayerHub.next(after: .appleMusic, in: [.appleMusic]) == nil, "alone, there is nowhere to go")
        report(PlayerHub.next(after: .none, in: [.appleMusic]) == .appleMusic, "from nothing to the one that plays")
    }

    private static func testBrowserScripts() {
        print("\n-- Browser page scripts (spec 014) --")
        let json = #"{"p":true,"t":42.5,"d":200,"ti":"Song","ar":"Artist","al":"","h":"www.youtube.com","i":"https://x/icon.png","u":"https://www.youtube.com/watch?v=1"}"#
        let parsed = BrowserMedia.parse(json)
        report(parsed?.isPlaying == true && parsed?.position == 42.5 && parsed?.host == "youtube.com", "an answer of the page is read")
        report(BrowserMedia.parse("") == nil && BrowserMedia.parse("{broken") == nil, "an empty or broken answer is nothing")
        report(BrowserMedia.appleScriptLiteral(#"a"b\c"#) == #""a\"b\\c""#, "a script is quoted for AppleScript")

        // The page: one video that plays, an icon, and Media Session.
        let context = JSContext()!
        context.evaluateScript("""
        var video = {paused:false, ended:false, readyState:4, muted:false, volume:1, currentTime:42.5, duration:200,
                     play:function(){this.paused=false;}, pause:function(){this.paused=true;}};
        var icon = {rel:'apple-touch-icon', href:'https://www.youtube.com/icon.png', getAttribute:function(){return '180x180';}};
        var clicked = '';
        var document = {title:'Song - YouTube',
            querySelectorAll:function(s){ return s.indexOf('video')>=0 ? (window.noMedia ? [] : [video]) : [icon]; },
            querySelector:function(s){ return s.indexOf('ytp-next-button')>=0 ? {click:function(){clicked='next';}} : null; }};
        var window = {noMedia:false};
        var navigator = {mediaSession:{metadata:{title:'Song', artist:'Artist', album:''}, playbackState:'playing'}};
        var location = {hostname:'www.youtube.com', origin:'https://www.youtube.com', href:'https://www.youtube.com/watch?v=1'};
        """)
        let answer = context.evaluateScript(BrowserMedia.readScript)?.toString() ?? ""
        let media = BrowserMedia.parse(answer)
        report(context.exception == nil && media?.title == "Song" && media?.artist == "Artist" && media?.isPlaying == true,
               "the read script finds the video and Media Session")
        report(media?.iconURL == "https://www.youtube.com/icon.png", "the read script picks the largest icon")

        _ = context.evaluateScript(BrowserMedia.commandScript(.playPause))
        report(context.evaluateScript("video.paused")?.toBool() == true, "play and pause act on the video")
        _ = context.evaluateScript(BrowserMedia.commandScript(.seek(90)))
        report(context.evaluateScript("video.currentTime")?.toDouble() == 90, "a seek moves the video")
        _ = context.evaluateScript(BrowserMedia.commandScript(.next))
        report(context.evaluateScript("clicked")?.toString() == "next", "next presses the page's own button")

        context.evaluateScript("window.noMedia = true; navigator.mediaSession.playbackState = 'none';")
        let nothing = context.evaluateScript(BrowserMedia.readScript)?.toString() ?? "x"
        report(nothing.isEmpty, "a page with nothing playing answers nothing")

        let cover = BrowserCover.make(icon: nil).flatMap(NSImage.init(data:))
        report((cover?.size.width ?? 0) >= 256, "a tab without an icon still gets a cover")
    }
}

// MARK: - Firefox, Zen and their kin (spec 014)

extension SelfTest {

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "  OK: \(what)" : "  !! FAIL: \(what)")
    }

    @MainActor
    static func testFirefoxFamily() {
        print("\n-- Firefox and Zen (spec 014) --")

        // A session file as Firefox writes it, with the format and the tabs of the real one.
        let svg = "data:image/svg+xml;base64," + Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><circle cx="16" cy="16" r="14" fill="red"/></svg>"#.utf8).base64EncodedString()
        let session: [String: Any] = ["windows": [["tabs": [
            ["index": 1, "entries": [["url": "about:blank", "title": ""]], "image": NSNull(), "lastAccessed": 1],
            ["index": 1, "entries": [["url": "https://chatgpt.com/g/x", "title": "Configurar dominio"]], "image": svg, "lastAccessed": 50],
            ["index": 2, "entries": [["url": "https://old.example/", "title": "Old"],
                                    ["url": "https://www.youtube.com/watch?v=1", "title": "(8606) No Te Ofendas/Ep 159: monetizar - YouTube"]],
             "image": "data:image/png;base64,AAAA", "lastAccessed": 100],
            ["index": 1, "entries": [["url": "https://www.youtube.com/watch?v=2", "title": "(3) No Te Ofendas/Ep 159: monetizar - YouTube"]],
             "image": "data:image/png;base64,BBBB", "lastAccessed": 300],
        ]]]]
        let json = (try? JSONSerialization.data(withJSONObject: session)) ?? Data()
        let file = FirefoxSession.compressForTest(json)
        check(FirefoxSession.decompress(file) == json, "the session file format (mozlz4) is decoded")
        check(FirefoxSession.decompress(Data("garbage garbage".utf8)) == nil, "a file that is not one is refused")
        // A block with a back reference, as real LZ4 makes: "abc", then 4 bytes copied from 3
        // back ("abca"), then the literals "xyz".
        let reference = FirefoxSession.lz4Block([0x30, 0x61, 0x62, 0x63, 0x03, 0x00, 0x30, 0x78, 0x79, 0x7A], size: 10)
        check(reference.map { String(decoding: $0, as: UTF8.self) } == "abcabcaxyz", "a back reference is copied")

        let tabs = FirefoxSession.tabs(from: file) ?? []
        check(tabs.count == 4, "the tabs are listed, each at its current entry")
        let match = FirefoxSession.match(tabs, title: "No Te Ofendas/Ep 159: monetizar", artist: "")
        check(match?.icon == "data:image/png;base64,BBBB", "the tab is found by the title that plays, the latest one on a tie")
        check(FirefoxSession.match(tabs, title: "Configurar dominio")?.url == "https://chatgpt.com/g/x", "an exact title wins")
        check(FirefoxSession.match(tabs, title: "A song that is in no tab") == nil, "no tab, no cover (the app's icon is used)")
        check(FirefoxSession.normalise("(8606) Ñandú - YouTube") == "nandu - youtube", "a counter and accents are ignored")
        check(FirefoxSession.isFirefoxFamily("app.zen-browser.zen") && !FirefoxSession.isFirefoxFamily("com.google.Chrome"),
              "Zen is of the family, Chrome is not")

        // The favicons.
        check(BrowserSource.decodeDataURL("data:text/plain;base64,aGk=") == Data("hi".utf8), "a base64 data URL is decoded")
        check(BrowserSource.decodeDataURL("data:text/plain,hi%20there") == Data("hi there".utf8), "a percent-encoded data URL is decoded")
        let cover = BrowserSource.decodeDataURL(svg).flatMap { BrowserCover.make(icon: $0) }.flatMap(NSImage.init(data:))
        check((cover?.size.width ?? 0) >= 256, "an SVG favicon becomes a cover")

        // What the system's library says.
        let line = #"{"b":"app.zen-browser.zen","p":true,"ti":"Song","ar":"Artist","al":"","t":12.5,"d":200,"r":1,"ts":\#(Date().timeIntervalSince1970 - 2)}"#
        let state = SystemNowPlaying.parse(Data(line.utf8))
        check(state?.bundleID == "app.zen-browser.zen" && state?.isPlaying == true && state?.title == "Song", "a line of the Now Playing library is read")
        check((state?.position ?? 0) > 14 && (state?.position ?? 0) < 15.5, "the position moves on from when it was sampled")
        check(SystemNowPlaying.parse(Data(#"{"error":"unavailable"}"#.utf8)) == nil && SystemNowPlaying.parse(Data("nope".utf8)) == nil,
              "an error or a broken line is nothing")
    }

    /// The real thing, with what is on this Mac: the library inside perl, and the session
    /// file of any Firefox-family browser. Only says what it found; it needs no browser.
    @MainActor
    static func testSystemNowPlayingLive() async {
        print("\n-- System Now Playing (this Mac) --")
        guard SystemNowPlaying.libraryURL() != nil else {
            print("  the adapter library is not here (build it with ./build-app.sh); Firefox and Zen cannot be read")
            return
        }
        SystemNowPlaying.shared.start()
        var state: SystemNowPlaying.State?
        for _ in 0..<30 where state == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
            state = SystemNowPlaying.shared.latest
        }
        check(state != nil, "the library runs inside perl and answers")
        if let state { print("  (information) now playing: \(state.bundleID) '\(state.title)' playing: \(state.isPlaying)") }
        SystemNowPlaying.shared.stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(!SystemNowPlaying.shared.isRunning, "it stops with the app")
        for (bundle, folder) in FirefoxSession.browsers where NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil {
            let tabs = FirefoxSession.allTabs(bundleID: bundle)
            guard !tabs.isEmpty else { continue }
            // The real session file: every tab with a title finds itself, and its icon.
            let withTitle = tabs.filter { $0.title.count >= 6 && !$0.url.hasPrefix("about:") }
            let found = withTitle.filter { FirefoxSession.match(tabs, title: $0.title) != nil }.count
            let icons = withTitle.filter { !$0.icon.isEmpty }.count
            print("  (information) \(folder): \(tabs.count) tabs read from the real session file, \(found)/\(withTitle.count) found by title, \(icons) with a favicon")
            check(found == withTitle.count, "every tab of the real session file is found by its own title")

            // End to end, if that browser is open: it "plays" a tab that really exists.
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundle }),
                  let tab = withTitle.first(where: { !$0.icon.isEmpty }) else { continue }
            let wasOn = AppSettings.shared.browserMedia
            AppSettings.shared.browserMedia = true
            SystemNowPlaying.shared.injected = SystemNowPlaying.State(
                bundleID: bundle, isPlaying: true, title: tab.title, artist: "Someone", album: "",
                elapsed: 30, duration: 300, rate: 1, timestamp: Date())
            defer {
                SystemNowPlaying.shared.injected = nil
                AppSettings.shared.browserMedia = wasOn
                SystemNowPlaying.shared.stop()
            }
            let source = BrowserSource()
            let snapshot: PlayerSnapshot = await withCheckedContinuation { continuation in source.readPosition { continuation.resume(returning: $0) } }
            check(snapshot.isPlaying && snapshot.title == tab.title && snapshot.positionSec >= 30, "\(folder): the source reads what the system says it plays")
            let metadata: PlayerTrackMetadata = await withCheckedContinuation { continuation in source.readTrack { continuation.resume(returning: $0) } }
            check(metadata.appBundleID == bundle && metadata.durationSec == 300 && !metadata.site.isEmpty, "\(folder): the site and the browser are known (\(metadata.site))")
            let cover = source.artworkData().flatMap(NSImage.init(data:))
            check((cover?.size.width ?? 0) >= 256, "\(folder): the favicon of the tab becomes the cover")
            source.send(.playPause)   // goes nowhere: the library is not running
        }
    }
}
