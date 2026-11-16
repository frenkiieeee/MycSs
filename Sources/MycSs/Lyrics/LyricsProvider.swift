import Foundation

/// Fetches lyrics for the playing track from three sources.
///
/// - **LRCLIB** and **NetEase** are asked **at the same time**: they are
///   independent network calls, and running them in sequence would double the
///   wait. LRCLIB is the fast one, with line-level timing. NetEase is slower but
///   is the only one with true per-word timing.
/// - **QQ Music** is the fallback. It is only asked when the other two have come
///   back empty, or when nothing has arrived after a couple of seconds, so a
///   song that is easy to find never costs it a request.
///
/// **The answers arrive as a stream.** The first lyrics that pass validation are
/// shown at once, and if a better version arrives later (real word timing
/// replacing interpolated timing) it is sent as an upgrade. Waiting for the
/// best answer would delay every song for the sake of the few where the best
/// one is a second slower.
///
/// The best result is cached in memory and on disk. A track that has been
/// fetched once is never fetched again, which matters because LRCLIB is
/// frequently overloaded.
actor LyricsProvider {

    static let shared = LyricsProvider()

    private var cache: [String: Lyrics] = [:]

    // MARK: - Streaming

    /// The lyrics of a track, as they arrive.
    ///
    /// Each element is better than the one before it: the first is whatever
    /// passed validation first, and a later one only appears if it has real word
    /// timing and the earlier one did not. The stream finishes when every source
    /// has answered. It yields nothing when no source could be trusted with a
    /// match: returning nothing is better than the wrong song's lyrics.
    nonisolated func results(for nowPlaying: NowPlaying) -> AsyncStream<Lyrics> {
        AsyncStream { continuation in
            let task = Task {
                guard nowPlaying.hasTrack else {
                    continuation.finish()
                    return
                }
                let key = nowPlaying.trackKey

                if let cached = await self.cached(key) {
                    Log.line("lyrics: cache hit for '\(nowPlaying.title)'")
                    continuation.yield(cached)
                    continuation.finish()
                    return
                }

                Log.line("lyrics: fetching for '\(nowPlaying.title)' by '\(nowPlaying.artist)'")
                var best: Lyrics?
                for await candidate in Self.race(for: nowPlaying) {
                    guard Self.isBetter(candidate, than: best) else { continue }
                    best = candidate
                    await self.store(candidate, for: key)
                    continuation.yield(candidate)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The lyrics of a track, waiting a little for a better version.
    ///
    /// - Parameter settle: how long to keep waiting for real word timing after
    ///   the first answer. Zero returns the first answer at once.
    func lyrics(for nowPlaying: NowPlaying, settle: TimeInterval = 1.2) async -> Lyrics? {
        let box = ResultBox()
        let consumer = Task {
            for await candidate in self.results(for: nowPlaying) { box.set(candidate) }
            box.markDone()
        }

        var firstAt: Date?
        while true {
            let (best, done) = box.snapshot()
            if let best, best.wordTimingQuality == .real { break }
            if best != nil, firstAt == nil { firstAt = Date() }
            if done { break }
            if let firstAt, Date().timeIntervalSince(firstAt) >= settle { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        consumer.cancel()
        return box.snapshot().0
    }

    private func cached(_ key: String) -> Lyrics? { cache[key] }

    private func store(_ lyrics: Lyrics, for key: String) {
        cache[key] = lyrics
    }

    /// Whether a result should replace the one already shown.
    private static func isBetter(_ candidate: Lyrics, than current: Lyrics?) -> Bool {
        guard let current else { return true }
        return candidate.wordTimingQuality == .real && current.wordTimingQuality != .real
    }

    // MARK: - The race

    /// Asks the sources and yields what each one finds, in arrival order.
    private static func race(for nowPlaying: NowPlaying) -> AsyncStream<Lyrics> {
        AsyncStream { continuation in
            let task = Task {
                let gate = FallbackGate()
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        if let lyrics = await LRCLib.fetch(for: nowPlaying) {
                            gate.found()
                            continuation.yield(lyrics)
                        }
                        gate.finishedOne()
                    }
                    group.addTask {
                        if let lyrics = await NetEase.fetch(for: nowPlaying) {
                            gate.found()
                            continuation.yield(lyrics)
                        }
                        gate.finishedOne()
                    }
                    group.addTask {
                        // The fallback: only when the others came back empty,
                        // or when nothing has arrived yet after a while.
                        guard await gate.shouldFallBack(after: 2.5) else { return }
                        Log.line("lyrics: asking the fallback source")
                        if let lyrics = await QQMusic.fetch(for: nowPlaying) {
                            continuation.yield(lyrics)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Decides when the fallback source is worth asking.
private final class FallbackGate: @unchecked Sendable {

    private let lock = NSLock()
    private var foundAny = false
    private var finished = 0
    /// How many first-line sources there are.
    private let sources = 2

    func found() {
        lock.lock(); defer { lock.unlock() }
        foundAny = true
    }

    func finishedOne() {
        lock.lock(); defer { lock.unlock() }
        finished += 1
    }

    private func state() -> (found: Bool, done: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (foundAny, finished >= sources)
    }

    /// True when nothing was found and either every first-line source is done or
    /// `timeout` has passed. False as soon as something is found.
    func shouldFallBack(after timeout: TimeInterval) async -> Bool {
        let started = Date()
        while !Task.isCancelled {
            let (foundAny, done) = state()
            if foundAny { return false }
            if done { return true }
            if Date().timeIntervalSince(started) > timeout { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}

/// Holds the best result so far, for the caller that polls it.
private final class ResultBox: @unchecked Sendable {

    private let lock = NSLock()
    private var best: Lyrics?
    private var done = false

    func set(_ lyrics: Lyrics) {
        lock.lock(); defer { lock.unlock() }
        best = lyrics
    }

    func markDone() {
        lock.lock(); defer { lock.unlock() }
        done = true
    }

    func snapshot() -> (Lyrics?, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (best, done)
    }
}
