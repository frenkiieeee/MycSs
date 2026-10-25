import Foundation

/// Keeps the lyrics in step with the music.
///
/// The position reported by Spotify is only sampled every poll, so between
/// polls it is *interpolated* from a monotonic clock. The highlight therefore
/// moves smoothly at frame rate instead of jumping once per poll.
///
/// **How the delay is kept low**: the fast reading asks for the position, the
/// playing state and the track title — about 25 ms. The title is what says
/// whether the track changed; the expensive metadata (artist, album, length) is
/// only fetched when the title changes, once per song instead of several times
/// per second. An earlier version asked for everything on every poll, which cost
/// 50 ms each time and showed up as a lag in the karaoke.
///
/// The interpolation is anchored to the last observed position and advanced by
/// the elapsed wall time, and re-anchored on every poll. If the polls drift
/// (because the machine was asleep, or the app was busy), the anchor is
/// corrected towards the new observation rather than being trusted blindly — a
/// jump larger than a threshold means the track was seeked.
actor SyncEngine {

    /// How often the position is sampled from Spotify.
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

    private var pollTask: Task<Void, Never>?

    // MARK: - Public state

    /// The track currently playing.
    var current: NowPlaying { nowPlaying }

    /// The lyrics for the current track, if they have loaded.
    var currentLyrics: Lyrics? { lyrics }

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
    /// Polling only runs while the overlay is on screen. With the Mac unlocked
    /// the app is idle: no polling, no network, no CPU.
    func start() {
        guard pollTask == nil else { return }
        Log.line("sync: polling started")
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let interval = self?.pollInterval ?? 0.2
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
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
            NowPlayingReader.readPosition { continuation.resume(returning: $0) }
        }
        await apply(snapshot)
    }

    private func apply(_ snapshot: NowPlayingReader.FastSnapshot) async {
        let observed = snapshot.positionSec
        let now = snapshot.takenAt

        // The playing state changed.
        if snapshot.isPlaying != !isPaused {
            isPaused = !snapshot.isPlaying
        }

        // A different title means a different track: fetch the rest of the
        // metadata. This is the reliable signal, and it happens once per song.
        if !snapshot.title.isEmpty, snapshot.title != loadedTitle {
            loadedTitle = snapshot.title
            await refreshTrackMetadata()
            // The position belongs to the new track, so the anchor is reset.
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
            NowPlayingReader.readTrack { continuation.resume(returning: $0) }
        }

        var track = nowPlaying
        track.title = loadedTitle
        track.artist = metadata.artist
        track.album = metadata.album
        track.durationSec = metadata.durationSec
        track.spotifyURL = metadata.spotifyURL
        track.source = .spotify
        track.isPlaying = !isPaused
        track.positionSec = anchorPosition
        nowPlaying = track

        Log.line("sync: track changed to '\(track.title)' by '\(track.artist)'")
        lyrics = nil
        await loadLyrics(for: track)
    }

    // MARK: - Lyrics

    private func loadLyrics(for nowPlaying: NowPlaying) async {
        guard let fetched = await LyricsProvider.shared.lyrics(for: nowPlaying) else {
            Log.line("sync: no lyrics for '\(nowPlaying.title)'")
            return
        }
        lyrics = fetched
        Log.line("""
        sync: lyrics loaded for '\(nowPlaying.title)' \
        (\(fetched.lines.count) lines, source \(fetched.source.rawValue), \
        word timing \(fetched.wordTimingQuality.rawValue))
        """)
    }
}
