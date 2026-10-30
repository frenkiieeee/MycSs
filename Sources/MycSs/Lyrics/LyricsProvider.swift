import Foundation

/// Fetches lyrics for the playing track, choosing between two sources.
///
/// Both providers are queried **at the same time**, because they are independent
/// network calls and running them in sequence would double the wait before the
/// lyrics appear. The provider with true per-word timing wins; otherwise the
/// line-level one does.
///
/// The result is cached in memory and on disk. A track that has been fetched
/// once is never fetched again, which matters because LRCLIB is frequently
/// overloaded.
actor LyricsProvider {

    static let shared = LyricsProvider()

    private var cache: [String: Lyrics] = [:]
    /// Keys currently being fetched, so a repeated request for the same track
    /// does not start a second fetch.
    private var inFlight: [String: Task<Lyrics?, Never>] = [:]

    /// Returns the lyrics for the given track.
    ///
    /// - Returns: the lyrics, or `nil` when no source could be trusted with a
    ///   match. Returning nil is better than returning the wrong song's lyrics.
    func lyrics(for nowPlaying: NowPlaying) async -> Lyrics? {
        guard nowPlaying.hasTrack else { return nil }
        let key = nowPlaying.trackKey

        if let cached = cache[key] {
            Log.line("lyrics: cache hit for '\(nowPlaying.title)'")
            return cached
        }

        if let existing = inFlight[key] {
            Log.line("lyrics: joining in-flight fetch for '\(nowPlaying.title)'")
            return await existing.value
        }

        let task = Task<Lyrics?, Never> { [weak self] in
            await self?.fetchFresh(for: nowPlaying)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil

        if let result {
            cache[key] = result
        }
        return result
    }

    /// Asks both providers and keeps the answer that comes first.
    ///
    /// The two are independent network calls, so they run at the same time.
    /// What matters is not to wait for both: LRCLIB is often overloaded and
    /// its retries add seconds, and there is no point in waiting for a second
    /// answer that is only marginally better.
    ///
    /// The one exception: a provider with real word timings is worth a short
    /// wait, because the karaoke is much more accurate with them.
    private func fetchFresh(for nowPlaying: NowPlaying) async -> Lyrics? {
        Log.line("lyrics: fetching for '\(nowPlaying.title)' by '\(nowPlaying.artist)'")

        return await withTaskGroup(of: Lyrics?.self) { group -> Lyrics? in
            group.addTask { await LRCLib.fetch(for: nowPlaying) }
            group.addTask { await NetEase.fetch(for: nowPlaying) }

            // A task that ends the waiting: if the other provider has not
            // answered by then, the first answer is good enough.
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                return nil
            }

            var best: Lyrics?

            for await result in group {
                guard let result else {
                    // The grace period is over.
                    if best != nil { break }
                    continue
                }

                if best == nil {
                    best = result
                    // Nothing better is coming if this one is already right.
                    if result.wordTimingQuality == .real { break }
                    continue
                }

                // The second answer: it only wins if it has real word timings.
                if result.wordTimingQuality == .real { best = result }
                break
            }

            return best
        }
    }
}
