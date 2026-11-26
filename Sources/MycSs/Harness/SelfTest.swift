import Foundation

/// Standalone checks against the real system.
///
/// Run it as:  ./MycSs.app/Contents/MacOS/MycSs --selftest
///
/// It exercises the pieces that depend on the outside world, the AppleScript
/// reader against the running Spotify app, the lock state, and the SkyLight
/// Space lookup, and prints the values so they can be compared by hand.
enum SelfTest {

    private static let source = SpotifySource()

    /// The checks that need no Spotify, no permission and no network. Used by CI.
    static func runPure() async {
        print("== MycSs self test (pure) ==")
        await SelfTest.testParsers()
        SelfTest.testVersioning()
        SelfTest.testKeyboardLightShortcut()
        await SelfTest.testBehaviour()
        print("\n== done ==")
    }

    static func run() async {
        print("== MycSs self test ==")
        print("platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 0. What needs no Spotify, no permission and no network goes first, so a
        // stuck permission prompt cannot hide it.
        await SelfTest.testParsers()
        SelfTest.testVersioning()
        SelfTest.testKeyboardLightShortcut()
        await SelfTest.testBehaviour()
        await SelfTest.testSystemNowPlayingLive()
        SelfTest.testKeyboardBacklight()

        // 1. AppleScript reader against the live Spotify app.
        let state = SelfTest.readTrack()
        let latency = SelfTest.measureLatency()
        print("\n-- SpotifySource --")
        print("  source:     \(state.source.rawValue)")
        print("  isPlaying:  \(state.isPlaying)")
        print("  title:      \(state.title)")
        print("  artist:     \(state.artist)")
        print("  album:      \(state.album)")
        print(String(format: "  position:   %.3f s", state.positionSec))
        print(String(format: "  duration:   %.3f s", state.durationSec))
        print(String(format: "  latency:    %.1f ms", latency * 1000))
        print("  trackKey:   \(state.trackKey)")

        // A position of exactly 0 on a playing track means the number parsing
        // failed: the locale hands back a comma and the naive parse yields nil.
        if state.isPlaying, state.positionSec == 0 {
            print("  !! WARNING: playing but position is 0 - number parsing failed")
        }

        // 1b. The same reading for Apple Music, and what the hub would pick.
        print("\n-- AppleMusicSource and PlayerHub --")
        let music = AppleMusicSource()
        let hub = PlayerHub()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            music.readPosition { snapshot in
                print("  music:   playing=\(snapshot.isPlaying) title='\(snapshot.title)' position=\(String(format: "%.2f", snapshot.positionSec)) latency=\(String(format: "%.1f", snapshot.latency * 1000)) ms")
                done.resume()
            }
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            hub.readPosition { snapshot in
                print("  hub:     follows \(hub.id.rawValue), title='\(snapshot.title)'")
                done.resume()
            }
        }

        // 1b2. Who macOS thinks this app is. A permission is tied to this.
        print("\n-- App identity --")
        let identity = AppIdentity.requirement
        print("  \(identity)")
        print(identity.hasPrefix("cdhash")
              ? "  (ad-hoc: changes with every build, so permissions are lost on each one)"
              : "  OK: tied to the certificate, stable between builds")

        // 1c. The commands the player controls send. They are only checked as text:
        // sending them would pause whatever the user is listening to.
        print("\n-- Player commands --")
        let seek = AppleScriptValue.statement(for: .seek(12.5))
        print("  seek:     \(seek)")
        print(seek == "set player position to 12.50"
              ? "  OK: the position is written with a point"
              : "  !! WARNING: the position must be written with a point, got '\(seek)'")
        print("  next:     \(AppleScriptValue.statement(for: .next))")
        print("  previous: \(AppleScriptValue.statement(for: .previous))")
        print("  playpause: \(AppleScriptValue.statement(for: .playPause))")

        // 2. Repeated reads, to confirm the position advances.
        print("\n-- position advance (2 reads, 1.2s apart) --")
        var positions: [Double] = []
        for i in 0..<2 {
            let snap = SelfTest.readPosition()
            positions.append(snap)
            print(String(format: "  read %d: %.3f s", i + 1, snap))
            if i == 0 {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        if positions[1] > positions[0] {
            print("  OK: position advances")
        } else {
            print("  (position did not advance - the track may be paused)")
        }

        // 3. Lock state.
        print("\n-- LockState --")
        let lock = LockState()
        lock.start()
        print("  isLocked:   \(lock.isLocked)")

        // 4. SkyLight Space lookup.
        print("\n-- SkyLight --")
        SkyLight.shared.rememberSpaces()
        let space = SkyLight.shared.newLockSpace()
        print("  new lock space: \(space.map(String.init) ?? "none")")
        print("  spaces: \(SkyLight.shared.describeSpaces())")

        // 6. Live lyric fetch for whatever is playing right now.
        await SelfTest.testProviders()

        print("\n== done ==")
    }

    // MARK: - Helpers

    /// Reads the track metadata the same way the app does.
    private static func readTrack() -> NowPlaying {
        var title = ""
        var result = NowPlaying()
        let semaphore = DispatchSemaphore(value: 0)
        // The title comes from the fast reading, the rest from the slow one.
        source.readPosition { snapshot in
            title = snapshot.title
            semaphore.signal()
        }
        semaphore.wait()

        let metadataSemaphore = DispatchSemaphore(value: 0)
        source.readTrack { metadata in
            result = NowPlaying()
            result.source = .spotify
            result.title = title
            result.artist = metadata.artist
            result.album = metadata.album
            result.durationSec = metadata.durationSec
            result.spotifyURL = metadata.trackURL
            metadataSemaphore.signal()
        }
        metadataSemaphore.wait()
        return result
    }

    /// Reads the position the same way the app does.
    private static func readPosition() -> Double {
        var result: Double = 0
        let semaphore = DispatchSemaphore(value: 0)
        source.readPosition { snapshot in
            result = snapshot.positionSec
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// The round-trip time of a position reading.
    private static func measureLatency() -> TimeInterval {
        var result: TimeInterval = 0
        let semaphore = DispatchSemaphore(value: 0)
        source.readPosition { snapshot in
            result = snapshot.latency
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    // MARK: - Parsers

    private static func testParsers() async {
        print("\n-- LyricsParser: LRC --")
        let lrc = """
        [00:12.34] We were both young when I first saw you
        [00:17.44] I close my eyes and the flashback starts
        [00:24.84] I'm standing there
        """
        let lrcLines = LyricsParser.parseLRC(lrc)
        for line in lrcLines {
            print(String(format: "  %.2fs  %@", line.startTime, line.text))
        }
        if lrcLines.count == 3, abs(lrcLines[0].startTime - 12.34) < 0.01 {
            print("  OK: 3 lines, first at 12.34s")
        } else {
            print("  !! WARNING: LRC parsing looks wrong")
        }

        print("\n-- LyricsParser: yrc --")
        let yrc = """
        {"t":-1000,"c":[{"tx":"作词: "},{"tx":"Jon Brion"}]}
        [0,5040](0,420,0)My (420,960,0)regrets (1380,360,0)look (1740,360,0)just
        [5040,3000](0,500,0)like (500,700,0)texts
        """
        let yrcLines = LyricsParser.parseYRC(yrc)
        for line in yrcLines {
            let words = line.words.map { String(format: "%.2f", $0.startTime) }.joined(separator: ", ")
            print(String(format: "  %.2fs  %@  [words: %@]", line.startTime, line.text, words))
        }
        if yrcLines.count == 2 {
            print("  OK: credit line dropped, 2 lyric lines")
        } else {
            print("  !! WARNING: yrc parsing looks wrong")
        }
        if let first = yrcLines.first, first.words.count == 4 {
            print("  OK: 4 words parsed with individual timings")
            let expected = [0.0, 0.42, 1.38, 1.74]
            let matches = zip(first.words, expected).allSatisfy { abs($0.startTime - $1) < 0.001 }
            print(matches ? "  OK: word offsets are correct" : "  !! WARNING: word offsets wrong")
        }

        print("\n-- WordInterpolator --")
        let interpolated = WordInterpolator.interpolate(lrcLines)
        if let line = interpolated.first {
            let words = line.words.map { String(format: "%.2f", $0.startTime) }.joined(separator: ", ")
            print("  first line words start at: \(words)")
            print("  pace: \(Int(WordInterpolator.derivePace(from: lrcLines)) ) ms/char")
            if line.words.count == 7 {
                print("  OK: 7 words synthesised")
            } else {
                print("  (words: \(line.words.count))")
            }
        }
    }

    // MARK: - Versioning

    private static func testVersioning() {
        print("\n-- Versioning --")
        let parsed = AppVersion.Semantic("v1.2.3")
        let ok = parsed.map { ($0.major, $0.minor, $0.patch) == (1, 2, 3) } ?? false
        print(ok ? "  OK: v1.2.3 parsed" : "  !! FAIL: v1.2.3 not parsed")
        let order = AppVersion.Semantic("0.2.5")! < AppVersion.Semantic("0.10.0")!
            && AppVersion.Semantic("1.0.0")! > AppVersion.Semantic("0.99.99")!
        print(order ? "  OK: versions compare as numbers, not as text" : "  !! FAIL: versions compare wrong")
        let beta = AppVersion.Semantic("1.0.0-beta.1")
        print(beta?.major == 1 ? "  OK: a pre-release suffix is ignored" : "  !! FAIL: pre-release not parsed")
        let newer = UpdateChecker.interpret(Data(#"{"tag_name":"v9.0.0","html_url":"https://example.com/r"}"#.utf8), current: "0.2.5")
        let same = UpdateChecker.interpret(Data(#"{"tag_name":"v0.2.5"}"#.utf8), current: "0.2.5")
        let broken = UpdateChecker.interpret(Data("nope".utf8), current: "0.2.5")
        var updatesOK = same == .upToDate
        if case .available = newer {} else { updatesOK = false }
        if case .failed = broken {} else { updatesOK = false }
        print(updatesOK ? "  OK: the release check tells newer, same and broken apart" : "  !! FAIL: release check wrong")
    }

    // MARK: - Keyboard light

    /// The shortcut logic, with no hardware: what is stored, how it reads, which keys
    /// are which, and that the modifiers have to be exactly the ones recorded.
    private static func testKeyboardLightShortcut() {
        print("\n-- Keyboard light shortcut --")
        func report(_ ok: Bool, _ what: String) { print(ok ? "  OK: \(what)" : "  !! FAIL: \(what)") }

        let up = KeyboardLightDirection.defaultUp, down = KeyboardLightDirection.defaultDown
        report(up.label == "⌥F2" && down.label == "⌥F1", "the defaults read ⌥F2 and ⌥F1")

        let custom = KeyChord(code: 40, modifiers: 6144, character: "k")
        report(KeyChord(stored: custom.stored) == custom && custom.label == "⌃⌥K", "a recorded shortcut survives being stored")
        report(KeyChord(stored: "nonsense") == nil && KeyChord(stored: "x|1") == nil, "a broken stored value is refused")

        // The brightness keys (3 down, 2 up) are F1 and F2 of an Apple keyboard.
        report(KeyChord.functionKey(forMediaKey: 3) == down.code && KeyChord.functionKey(forMediaKey: 2) == up.code,
               "the brightness keys are F1 and F2")
        report(KeyChord.functionKey(forMediaKey: 99) == nil, "an unknown media key is not a function key")

        func which(_ code: Int, _ modifiers: Int) -> KeyboardLightDirection? {
            KeyboardLightDirection.direction(code: code, modifiers: modifiers, up: up, down: down)
        }
        report(which(120, up.modifiers) == .up && which(122, up.modifiers) == .down, "⌥F2 raises and ⌥F1 lowers")
        report(which(120, 0) == nil && which(122, 0) == nil, "plain F1 and F2 stay the screen brightness")
        report(which(122, up.modifiers | 512) == nil, "⌥⇧F1 stays the fine step of the screen brightness")
        report(KeyboardLightDirection.direction(code: 120, modifiers: up.modifiers, up: nil, down: nil) == nil, "a cleared shortcut does nothing")

        report(KeyChord.isValid(code: 122, modifiers: 0), "an F key needs no modifier")
        report(!KeyChord.isValid(code: 40, modifiers: 0) && !KeyChord.isValid(code: 40, modifiers: 512)
               && KeyChord.isValid(code: 40, modifiers: 2048), "a letter needs Control, Option or Command")

        // What the user had stored (nothing, or their own shortcuts), to leave it as it was.
        let keys = [SettingKey.keyboardLightUp, SettingKey.keyboardLightDown]
        let stored = keys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        AppSettings.shared.keyboardLightUp = nil
        let cleared = AppSettings.shared.keyboardLightUp == nil
        AppSettings.shared.resetKeyboardLightShortcuts()
        let back = AppSettings.shared.keyboardLightUp == up && AppSettings.shared.keyboardLightDown == down
        for (key, value) in stored {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        report(cleared && back, "clearing and restoring the shortcuts in the settings")
    }

    /// The real light of this Mac, if it has one: it is read, and the same value is
    /// written back; then it goes up a step and returns to where it was.
    private static func testKeyboardBacklight() {
        print("\n-- Keyboard light (this Mac) --")
        guard KeyboardBacklight.isAvailable, let before = KeyboardBacklight.level() else {
            print("  no keyboard light here (or CoreBrightness changed): the shortcut stays inactive")
            return
        }
        print(String(format: "  level: %.3f", before))
        let rewrote = KeyboardBacklight.set(before)
        let moved = KeyboardBacklight.step(up: before < 0.5)
        let changed = moved.map { abs($0 - before) > 0.01 } ?? false
        KeyboardBacklight.set(before)
        let restored = KeyboardBacklight.level().map { abs($0 - before) < 0.02 } ?? false
        print(rewrote ? "  OK: the same value is written back" : "  !! FAIL: could not write the light")
        print(changed ? "  OK: a step moves the light" : "  !! FAIL: a step did not move the light")
        print(restored ? "  OK: the light is back where it was" : "  !! FAIL: the light was not restored")
    }

    // MARK: - Providers

    private static func testProviders() async {
        let state = SelfTest.readTrack()
        guard state.hasTrack else {
            print("\n-- Providers --")
            print("  (nothing playing, skipping)")
            return
        }

        print("\n-- Providers (live) --")
        print("  querying for '\(state.title)' by '\(state.artist)' (\(Int(state.durationSec))s)")

        let started = Date()
        let lyrics = await LyricsProvider.shared.lyrics(for: state)
        let elapsed = Date().timeIntervalSince(started)

        guard let lyrics else {
            print("  !! no lyrics found")
            return
        }

        print(String(format: "  fetched in %.2fs", elapsed))
        print("  source:      \(lyrics.source.rawValue)")
        print("  word timing: \(lyrics.wordTimingQuality.rawValue)")
        print("  lines:       \(lyrics.lines.count)")

        // Show the lines around the current position.
        let active = lyrics.activeLineIndex(at: state.positionSec)
        print("  active index at \(Int(state.positionSec))s: \(active.map(String.init) ?? "none")")

        let window = lyrics.lines.indices.filter { index in
            abs(lyrics.lines[index].startTime - state.positionSec) < 25
        }
        for index in window.prefix(6) {
            let line = lyrics.lines[index]
            let marker = index == active ? ">>" : "  "
            print(String(format: "  %@ %7.2fs  %@", marker, line.startTime, line.text))
            if index == active, line.hasWordTiming {
                let words = line.words.map { String(format: "%.2f", $0.startTime) }.joined(separator: ", ")
                print("       words at: \(words)")
            }
        }
    }
}
