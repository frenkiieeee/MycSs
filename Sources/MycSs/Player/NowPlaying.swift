import Foundation

/// A snapshot of what Spotify is playing right now.
struct NowPlaying: Equatable {

    /// Which player the snapshot came from.
    enum Source: String {
        case spotify
        case none
    }

    var source: Source = .none
    var isPlaying: Bool = false
    var title: String = ""
    var artist: String = ""
    var album: String = ""

    /// Playback position in seconds.
    var positionSec: Double = 0
    /// Track length in seconds.
    var durationSec: Double = 0

    /// The track's Spotify URL, when it is known.
    var spotifyURL: String?

    var hasTrack: Bool { !title.isEmpty }

    /// A stable key for caching: the same song must produce the same key whether
    /// it came from a poll or from a track change.
    var trackKey: String {
        "\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())"
    }

    /// The Spotify track id, extracted from `spotify:track:<id>`.
    var spotifyTrackID: String? {
        guard let spotifyURL, spotifyURL.hasPrefix("spotify:track:") else { return nil }
        return String(spotifyURL.dropFirst("spotify:track:".count))
    }
}
