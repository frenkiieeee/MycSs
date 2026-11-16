import Foundation

/// A fast reading of a player: where the playhead is, whether it is moving, and
/// the title that identifies the track.
struct PlayerSnapshot {
    var isPlaying: Bool
    var positionSec: TimeInterval
    /// The title of the track, used to detect a change.
    var title: String
    var latency: TimeInterval
    var takenAt: Date
}

/// The metadata that is expensive to read, fetched once per track.
struct PlayerTrackMetadata {
    var artist: String
    var album: String
    var durationSec: Double
    /// The player's own URL for the track (`spotify:track:<id>`), when it has one.
    var trackURL: String?
}

/// What the player controls can ask a player to do.
enum PlayerCommand: Equatable {
    case playPause
    case next
    /// Goes back to the previous track. The engine turns it into "restart this
    /// one" when the track is already a few seconds in, like every player does.
    case previous
    /// Jumps to a position, in seconds.
    case seek(TimeInterval)
}

/// Something that can tell MycSs what is playing.
///
/// Every player talks to its app in its own way (today AppleScript), but the
/// rest of the app only needs these four things, so a new player is one new
/// conformance and nothing else changes.
///
/// The reading is split in two on purpose: `readPosition` is cheap and runs
/// several times per second, `readTrack` is expensive and only runs when the
/// title changes. See `SpotifySource` for the measurements behind that.
protocol PlayerSource {

    /// Which player this is, recorded on every `NowPlaying` it produces.
    var id: NowPlaying.Source { get }

    /// Reads position, state and title, off the main thread.
    func readPosition(completion: @escaping (PlayerSnapshot) -> Void)

    /// Reads the rest of the track's metadata, off the main thread.
    func readTrack(completion: @escaping (PlayerTrackMetadata) -> Void)

    /// The artwork URL of the current track, when the player exposes one.
    func artworkURL() -> String?

    /// The artwork itself, for players that hand over the image and not a URL.
    func artworkData() -> Data?

    /// Sends a command to the player, off the main thread.
    func send(_ command: PlayerCommand)
}

extension PlayerSource {
    func artworkData() -> Data? { nil }
    func send(_ command: PlayerCommand) {}
}
