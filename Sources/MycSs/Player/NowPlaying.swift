import Foundation

/// A snapshot of what is playing right now, in Spotify, Music or a browser tab.
struct NowPlaying: Equatable {

    /// Which player the snapshot came from.
    enum Source: String {
        case spotify
        case appleMusic
        /// A tab of a web browser (spec 014).
        case browser
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

    /// The track's Spotify URL, when it is known (for a browser tab, the page's).
    var spotifyURL: String?
    /// For a browser tab: the site (`youtube.com`) and the browser's bundle, to show
    /// where the sound comes from.
    var siteName: String = ""
    var appBundleID: String = ""

    var hasTrack: Bool { !title.isEmpty }

    /// A stable key for caching: the same song must produce the same key whether
    /// it came from a poll or from a track change.
    var trackKey: String {
        "\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())"
    }

    /// A Spotify item that is not a song: the DJ talking (`spotify:media:`, title "Up
    /// next", album "DJ"), a podcast or an ad. It has no lyrics, and every DJ segment
    /// has the same title, so it cannot share one cover key.
    var isSpotifyNonSong: Bool {
        guard source == .spotify, let spotifyURL, !spotifyURL.isEmpty else { return false }
        return !spotifyURL.hasPrefix("spotify:track:") && !spotifyURL.hasPrefix("spotify:local:")
    }

    /// The key of the cover: the song's, or each DJ segment's own item.
    var coverKey: String {
        isSpotifyNonSong ? trackKey + "|" + (spotifyURL ?? "") : trackKey
    }

    /// Whether the cover can only come from the player (never the disk cache or the
    /// catalogues): a browser tab, or a Spotify item that is not a song.
    var coverFromPlayerOnly: Bool { source == .browser || isSpotifyNonSong }

    /// The Spotify track id, extracted from `spotify:track:<id>`.
    var spotifyTrackID: String? {
        guard let spotifyURL, spotifyURL.hasPrefix("spotify:track:") else { return nil }
        return String(spotifyURL.dropFirst("spotify:track:".count))
    }
}
