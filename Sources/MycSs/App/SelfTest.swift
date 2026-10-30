import Foundation

/// Standalone checks against the real system.
///
/// Run it as:  ./MycSs.app/Contents/MacOS/MycSs --selftest
///
/// It exercises the pieces that depend on the outside world — the AppleScript
/// reader against the running Spotify app, the lock state, and the SkyLight
/// Space lookup — and prints the values so they can be compared by hand.
enum SelfTest {

    static func run() async {
        print("== MycSs self test ==")
        print("platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 1. AppleScript reader against the live Spotify app.
        let state = SelfTest.readTrack()
        let latency = SelfTest.measureLatency()
        print("\n-- NowPlayingReader --")
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

        // 5. How stale is the reading really?
        LatencyProbe.run()

        // 6. Parser checks against the real formats.
        await SelfTest.testParsers()

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
        NowPlayingReader.readPosition { snapshot in
            title = snapshot.title
            semaphore.signal()
        }
        semaphore.wait()

        let metadataSemaphore = DispatchSemaphore(value: 0)
        NowPlayingReader.readTrack { metadata in
            result = NowPlaying()
            result.source = .spotify
            result.title = title
            result.artist = metadata.artist
            result.album = metadata.album
            result.durationSec = metadata.durationSec
            result.spotifyURL = metadata.spotifyURL
            metadataSemaphore.signal()
        }
        metadataSemaphore.wait()
        return result
    }

    /// Reads the position the same way the app does.
    private static func readPosition() -> Double {
        var result: Double = 0
        let semaphore = DispatchSemaphore(value: 0)
        NowPlayingReader.readPosition { snapshot in
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
        NowPlayingReader.readPosition { snapshot in
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
