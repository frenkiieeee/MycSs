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

    /// Asks both providers in parallel and keeps the better answer.
    private func fetchFresh(for nowPlaying: NowPlaying) async -> Lyrics? {
        Log.line("lyrics: fetching for '\(nowPlaying.title)' by '\(nowPlaying.artist)'")

        // Musixmatch is only consulted when it has been configured with an API
        // key; without one it is skipped rather than failing.
        async let lrclibResult = LRCLib.fetch(for: nowPlaying)
        async let neteaseResult = NetEase.fetch(for: nowPlaying)
        async let musixmatchResult = Musixmatch.isConfigured
            ? Musixmatch.fetch(for: nowPlaying)
            : nil

        let (fromLRCLib, fromNetEase, fromMusixmatch) = await (lrclibResult, neteaseResult, musixmatchResult)

        // Real per-word timing is worth more than anything else. Musixmatch's
        // richsync is character-level, so it is the best of the three.
        if let musixmatch = fromMusixmatch, musixmatch.wordTimingQuality == .real {
            Log.line("lyrics: using musixmatch (per-character timing)")
            return musixmatch
        }
        if let netease = fromNetEase, netease.wordTimingQuality == .real {
            Log.line("lyrics: using netease (real word timings)")
            return netease
        }
        if let musixmatch = fromMusixmatch {
            Log.line("lyrics: using musixmatch")
            return musixmatch
        }
        if let lrclib = fromLRCLib {
            Log.line("lyrics: using lrclib")
            return lrclib
        }
        if let netease = fromNetEase {
            Log.line("lyrics: using netease (interpolated)")
            return netease
        }

        Log.line("lyrics: no source produced a usable match")
        return nil
    }
}
