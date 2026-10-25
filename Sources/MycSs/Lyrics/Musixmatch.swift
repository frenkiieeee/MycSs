import Foundation

/// Fetches lyrics from Musixmatch.
///
/// Musixmatch is the catalogue behind most of the lyrics in the world, and it
/// has the best karaoke data available: the `richsync` format carries a
/// **per-character offset**, which is finer-grained than anything else the app
/// can get.
///
/// **An API key is required.** The public endpoints answer `401` without one
/// (the HTTP status is 200 and the error is in the body, which is easy to
/// misread). The key is read from the keychain; the user gets a free one from
/// <https://www.musixmatch.com/developer>.
///
/// **Why it is optional**: the app works without it, using LRCLIB and NetEase.
/// A Musixmatch key simply adds a third source, and the one with the finest
/// timing.
///
/// **Why the Spotify id is the key to the lookup**: `track.lyrics.get` accepts
/// `track_spotify_id`, and the app already knows the Spotify id of the playing
/// track (it comes from the desktop app). So there is no fuzzy matching: the
/// lookup is exact.
enum Musixmatch {

    /// The account name the API key is stored under in the keychain.
    static let keychainAccount = "musixmatch-api-key"

    /// The API key, if the user has configured one.
    static var apiKey: String? {
        guard let key = Keychain.get(account: keychainAccount) else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether Musixmatch is available.
    static var isConfigured: Bool { apiKey != nil }

    /// Stores the API key.
    static func setAPIKey(_ key: String) {
        if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Keychain.remove(account: keychainAccount)
        } else {
            Keychain.set(key, account: keychainAccount)
        }
    }

    // MARK: - Fetching

    /// Fetches the lyrics for a track.
    ///
    /// - Parameter track: the track as Spotify reports it, including its
    ///   Spotify id.
    /// - Returns: the lyrics, or `nil` when there is no match.
    static func fetch(for track: NowPlaying) async -> Lyrics? {
        guard let key = apiKey else {
            Log.line("musixmatch: no API key configured, skipping")
            return nil
        }

        // The Spotify id makes the lookup exact, so it is preferred. When it is
        // missing (a local file, for instance) the title and artist are used
        // instead.
        let spotifyID = track.spotifyTrackID

        if let spotifyID {
            if let lyrics = await fetchRichSync(spotifyID: spotifyID, apiKey: key) {
                return lyrics
            }
            if let lyrics = await fetchPlainLyrics(spotifyID: spotifyID, apiKey: key) {
                return lyrics
            }
            Log.line("musixmatch: nothing for spotify id \(spotifyID)")
            return nil
        }

        return await fetchByName(title: track.title, artist: track.artist, apiKey: key)
    }

    // MARK: - Rich sync (per-character timing)

    /// Fetches the rich sync, which has the finest timing.
    private static func fetchRichSync(spotifyID: String, apiKey: String) async -> Lyrics? {
        guard let url = makeURL(
            path: "/ws/1.1/track.richsync.get",
            apiKey: apiKey,
            parameters: ["track_spotify_id": spotifyID]
        ) else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let body = parseEnvelope(data),
              let richSync = body["richsync"] as? [String: Any],
              let richSyncBody = richSync["richsync_body"] as? String
        else {
            Log.line("musixmatch: no richsync for \(spotifyID)")
            return nil
        }

        guard let parsed = LyricsParser.parseRichSync(richSyncBody) else {
            Log.line("musixmatch: richsync could not be parsed")
            return nil
        }

        Log.line("musixmatch: \(parsed.count) lines with per-character timing")
        return Lyrics(
            lines: parsed,
            duration: richSync["richsync_length"] as? Double ?? 0,
            source: .musixmatch,
            wordTimingQuality: .real
        )
    }

    // MARK: - Plain lyrics

    /// Fetches the plain (unsynced) lyrics, as a last resort.
    private static func fetchPlainLyrics(spotifyID: String, apiKey: String) async -> Lyrics? {
        guard let url = makeURL(
            path: "/ws/1.1/track.lyrics.get",
            apiKey: apiKey,
            parameters: ["track_spotify_id": spotifyID]
        ) else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let body = parseEnvelope(data),
              let lyrics = body["lyrics"] as? [String: Any],
              let lyricsBody = lyrics["lyrics_body"] as? String,
              !lyricsBody.isEmpty
        else { return nil }

        var lines = LyricsParser.parsePlainLyrics(lyricsBody)
        lines = LyricsParser.filteringCredits(lines)
        guard !lines.isEmpty else { return nil }

        lines = WordInterpolator.interpolate(lines)
        Log.line("musixmatch: \(lines.count) plain lines, word timings interpolated")
        return Lyrics(
            lines: lines,
            duration: 0,
            source: .musixmatch,
            wordTimingQuality: .interpolated
        )
    }

    // MARK: - Lookup by name

    /// Finds the lyrics by title and artist, for when there is no Spotify id.
    private static func fetchByName(title: String, artist: String, apiKey: String) async -> Lyrics? {
        guard let url = makeURL(
            path: "/ws/1.1/macro.subtitles.get",
            apiKey: apiKey,
            parameters: [
                "q_track": title,
                "q_artist": artist,
                "namespace": "lyrics_richsynched",
            ]
        ) else { return nil }

        guard let data = await HTTPCache.shared.data(for: url),
              let body = parseEnvelope(data),
              let calls = body["macro_calls"] as? [String: Any]
        else { return nil }

        // The macro endpoint nests the result one level deeper.
        let richSync = (calls["track.richsync.get"] as? [String: Any])?
            .compactMapValues { $0 as? [String: Any] }["message"]
            .flatMap { ($0 as? [String: Any])?["body"] as? [String: Any] }
            .flatMap { ($0 as? [String: Any])?["richsync"] as? [String: Any] }

        if let richSync, let richSyncBody = richSync["richsync_body"] as? String,
           let parsed = LyricsParser.parseRichSync(richSyncBody) {
            Log.line("musixmatch: \(parsed.count) lines by name, per-character timing")
            return Lyrics(
                lines: parsed,
                duration: richSync["richsync_length"] as? Double ?? 0,
                source: .musixmatch,
                wordTimingQuality: .real
            )
        }

        Log.line("musixmatch: no match for '\(title)' by '\(artist)'")
        return nil
    }

    // MARK: - Networking

    private static func makeURL(path: String, apiKey: String, parameters: [String: String]) -> URL? {
        guard var components = URLComponents(string: "https://api.musixmatch.com" + path) else {
            return nil
        }
        var items = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "format", value: "json"))
        items.append(URLQueryItem(name: "apikey", value: apiKey))
        components.queryItems = items
        return components.url
    }

    /// Unwraps Musixmatch's envelope and checks the status.
    ///
    /// The service answers with HTTP 200 even for errors; the real status is in
    /// the body, so it has to be read there.
    private static func parseEnvelope(_ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let header = message["header"] as? [String: Any],
              let status = header["status_code"] as? Int
        else { return nil }

        guard status == 200 else {
            Log.line("musixmatch: status \(status)")
            return nil
        }
        return message["body"] as? [String: Any]
    }
}
