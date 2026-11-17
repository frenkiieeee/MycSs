import Foundation

/// Keeps the lyrics in step with the music.
///
/// The position reported by Spotify is only sampled every poll, so between
/// polls it is *interpolated* from a monotonic clock. The highlight therefore
/// moves smoothly at frame rate instead of jumping once per poll.
///
/// **How the delay is kept low**: the fast reading asks for the position, the
/// playing state and the track title, about 25 ms. The title is what says
/// whether the track changed; the expensive metadata (artist, album, length) is
/// only fetched when the title changes, which happens once per song instead of
/// several times per second. An earlier version asked for everything on every
/// poll, which cost 50 ms each time and showed up as a lag in the karaoke.
///
/// The interpolation is anchored to the last observed position and advanced by
/// the elapsed wall time, and re-anchored on every poll. If the polls drift
/// (because the machine was asleep, or the app was busy), the anchor is
/// corrected towards the new observation rather than being trusted blindly, a
/// jump larger than a threshold means the track was seeked.
actor SyncEngine {

    /// The player being read. Spotify today; any `PlayerSource` works.
    private let source: any PlayerSource

    init(source: any PlayerSource) {
        self.source = source
    }

    /// How often the position is sampled from the player.
    private let pollInterval: TimeInterval = 0.2

    /// Position differences larger than this are treated as a seek rather than
    /// as normal drift.
    private static let largeJumpThreshold: TimeInterval = 4.0

    private var nowPlaying = NowPlaying()
    private var lyrics: Lyrics?

    /// The position and the moment it was observed. The pair is the anchor the
    /// interpolation works from.
    private var anchorPosition: TimeInterval = 0
    private var anchorDate: Date = Date()
    /// Set when the position is known not to be advancing (the track is paused).
    private var isPaused = false

    /// The title of the track whose metadata is currently loaded.
    private var loadedTitle: String = ""
    /// Whether a metadata read is already in flight.
    private var isLoadingTrack = false
    /// Whether the lyrics of the current track are being fetched.
    private var isLoading = false

    private var pollTask: Task<Void, Never>?

    // MARK: - Public state

    /// The track currently playing.
    var current: NowPlaying { nowPlaying }

    /// True once every source has answered and none had lyrics for the track.
    ///
    /// The overlay uses it to move the cover to the middle of the screen.
    private(set) var lyricsNotFound = false

    /// The task that fetches the lyrics of the current track.
    private var lyricsTask: Task<Void, Never>?

    /// Whether a track is loaded and the player is moving.
    var isPlaying: Bool { !isPaused && nowPlaying.hasTrack }

    /// The lyrics for the current track, if they have loaded.
    var currentLyrics: Lyrics? { lyrics }

    /// Whether the lyrics are still being fetched.
    ///
    /// The overlay uses this to show the artwork on its own while it waits.
    var isLoadingLyrics: Bool { isLoading }

    /// The interpolated playback position, in seconds.
    var position: TimeInterval {
        guard !isPaused else { return anchorPosition }
        return anchorPosition + Date().timeIntervalSince(anchorDate)
    }

    /// The index of the line that is active right now.
    var activeLineIndex: Int? {
        lyrics?.activeLineIndex(at: position)
    }

    /// The line that is active right now.
    var activeLine: LyricLine? {
        guard let lyrics, let index = activeLineIndex, index < lyrics.lines.count else { return nil }
        return lyrics.lines[index]
    }

    // MARK: - Lifecycle

    /// Starts polling Spotify.
    ///
    /// Polling runs the whole time the app is running, locked or not. That is
    /// deliberate: while the Mac is unlocked the app knows which track is
    /// playing, so when the screen is locked the lyrics are already on their way
    /// and appear immediately instead of a second and a half later.
    ///
    /// Nothing is drawn while unlocked, and the app only makes network requests
    /// when the track actually changes.
    func start() {
        guard pollTask == nil else { return }
        Log.line("sync: polling started")

        // Read the track straight away.
        Task { await poll() }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? 0.2
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.poll()
            }
        }
    }

    // MARK: - Commands

    /// Sends a command to the player and updates the picture straight away.
    ///
    /// The player takes a moment to answer, and the poll is five times a second
    /// at best, so waiting for it would make every button feel dead. The
    /// position is moved at once, and the next poll corrects it if the player
    /// disagrees.
    func perform(_ command: PlayerCommand) {
        switch command {
        case .playPause:
            if isPaused {
                anchorDate = Date()
            } else {
                anchorPosition = position
            }
            isPaused.toggle()
            source.send(.playPause)

        case .next:
            source.send(.next)

        case .previous:
            // Past the first few seconds, "previous" restarts the song.
            if position > 3 {
                perform(.seek(0))
                return
            }
            source.send(.previous)

        case .seek(let seconds):
            let target = nowPlaying.durationSec > 0
                ? min(max(seconds, 0), nowPlaying.durationSec)
                : max(seconds, 0)
            anchorPosition = target
            anchorDate = Date()
            source.send(.seek(target))
        }

        // A reading soon after, so a skipped track or a refused command shows.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.poll()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        Log.line("sync: polling stopped")
    }

    // MARK: - Polling

    private func poll() async {
        let snapshot = await withCheckedContinuation { continuation in
            source.readPosition { continuation.resume(returning: $0) }
        }
        await apply(snapshot)
    }

    private func apply(_ snapshot: PlayerSnapshot) async {
        let observed = snapshot.positionSec
        let now = snapshot.takenAt

        // The playing state changed.
        if snapshot.isPlaying != !isPaused {
            isPaused = !snapshot.isPlaying
        }

        // A different title means a different track: fetch the rest of the
        // metadata and the lyrics. This is the reliable signal, and it happens
        // once per song.
        //
        // This check comes first on purpose: it is also what handles the very
        // first reading of a session, where the title is new. Returning early
        // there would leave the app without lyrics until the next song.
        if !snapshot.title.isEmpty, snapshot.title != loadedTitle {
            loadedTitle = snapshot.title
            await refreshTrackMetadata()
            // The position belongs to the new track, so the anchor is reset.
            anchorPosition = observed
            anchorDate = now
            return
        }

        // The very first reading has no anchor to compare against: the position
        // is simply taken as it is, without reporting a phantom seek.
        if loadedTitle.isEmpty, nowPlaying.title.isEmpty {
            anchorPosition = observed
            anchorDate = now
            return
        }

        // Check for a seek.
        let predicted = position
        let difference = observed - predicted

        if abs(difference) > Self.largeJumpThreshold {
            // A seek, or the track restarted. Re-anchor without interpolating
            // across the jump.
            Log.line("""
            sync: seek detected (observed \(observed), expected \(predicted))
            """)
            anchorPosition = observed
        } else {
            // Normal drift: move the anchor a little towards the observation.
            // Trusting the observation completely would make the highlight jump
            // backwards on every poll, because the sample is always a little
            // stale. The correction is weighted so a single noisy sample
            // cannot yank the highlight.
            anchorPosition += difference * 0.5
        }
        anchorDate = now
    }

    // MARK: - Track metadata

    /// Fetches the metadata of the current track.
    ///
    /// This is the expensive read, so it only happens when the track changes.
    private func refreshTrackMetadata() async {
        guard !isLoadingTrack else { return }
        isLoadingTrack = true
        defer { isLoadingTrack = false }

        let metadata = await withCheckedContinuation { continuation in
            source.readTrack { continuation.resume(returning: $0) }
        }

        var track = nowPlaying
        track.title = loadedTitle
        track.artist = metadata.artist
        track.album = metadata.album
        track.durationSec = metadata.durationSec
        track.spotifyURL = metadata.trackURL
        track.source = source.id
        track.isPlaying = !isPaused
        track.positionSec = anchorPosition
        nowPlaying = track

        Log.line("sync: track changed to '\(track.title)' by '\(track.artist)'")
        lyrics = nil
        lyricsNotFound = false
        isLoading = true

        // The lyrics are fetched in a task of their own. Waiting for them here
        // would stop the polling, and with it the position, for as long as the
        // sources take, and a later upgrade (real word timing) would keep it
        // stopped even longer.
        lyricsTask?.cancel()
        lyricsTask = Task { [weak self] in await self?.loadLyrics(for: track) }
    }

    // MARK: - Lyrics

    /// Fetches the lyrics and keeps listening for a better version.
    ///
    /// The first answer is shown at once. A later one replaces it only when it
    /// has real word timing and the first did not (`LyricsProvider` decides).
    private func loadLyrics(for track: NowPlaying) async {
        var found = await receive(from: LyricsProvider.shared.results(for: track), for: track)
        guard !Task.isCancelled, loadedTitle == track.title else { return }
        isLoading = false
        guard !found else { return }

        // Nothing found. The overlay moves the cover to the middle, and one more
        // try is made a little later: the sources fail in bursts (LRCLIB answers
        // 503 for a minute at a time), and a song that is missing now is often
        // there a few seconds on.
        lyricsNotFound = true
        Log.line("sync: no lyrics for '\(track.title)', trying again in 8 s")

        try? await Task.sleep(nanoseconds: 8_000_000_000)
        guard !Task.isCancelled, loadedTitle == track.title else { return }

        found = await receive(from: LyricsProvider.shared.results(for: track), for: track)
        if found { Log.line("sync: the second try found lyrics for '\(track.title)'") }
    }

    /// Takes the lyrics from the stream as they arrive. Returns whether any did.
    private func receive(from stream: AsyncStream<Lyrics>, for track: NowPlaying) async -> Bool {
        var found = false
        for await result in stream {
            guard !Task.isCancelled, loadedTitle == track.title else { return found }
            lyrics = result
            lyricsNotFound = false
            isLoading = false
            found = true
            Log.line("""
            sync: lyrics for '\(track.title)' from \(result.source.rawValue) \
            (\(result.lines.count) lines, word timing \(result.wordTimingQuality.rawValue))
            """)
        }
        return found
    }
}
