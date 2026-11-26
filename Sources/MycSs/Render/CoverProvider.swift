import AppKit
import CryptoKit
import Foundation

/// Finds the album cover of the playing track, from the best place it can.
///
/// 1. **The disk cache.** A cover that was found once is never searched again,
///    and it is there at once when the same song comes round.
/// 2. **The player.** Spotify gives a URL and Music hands over the image. The URL
///    can still be the *previous* song's for a while after a change (with Spotify's
///    DJ, for seconds), so every URL is remembered with the song it belongs to, and
///    a URL that belongs to another song is never used (it is asked again, and if
///    it does not change the catalogues are searched instead). Before this, a cover
///    found in the cache left no URL to compare with, and the next song could keep
///    the previous singer's cover for good.
/// 3. **Apple's catalogue** (the iTunes Search API) and then **Deezer's**, both
///    public and without a key, for what the player does not have: local files,
///    songs Music cannot give the artwork of, a URL that never arrives. Their
///    covers are large (up to 1000 px). A result is only used when its title and
///    artist match, because a wrong cover is worse than none.
actor CoverProvider {

    static let shared = CoverProvider()

    private var memory: [String: NSImage] = [:]
    /// Which song each player URL was seen with, to notice a URL that is still the
    /// previous song's.
    private var urlOwner: [String: String] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// What a lookup found, and where, for the log and the bench.
    enum Origin: String {
        case memory, disk, player, itunes, deezer
    }

    /// The cover of a track.
    ///
    /// - Parameters:
    ///   - track: what is playing.
    ///   - previousURL: the artwork URL of the song before, to notice a stale one.
    ///   - readPlayer: asks the player, which can take a moment; it runs off the
    ///     main thread.
    func cover(
        for track: NowPlaying,
        previousURL: String?,
        readPlayer: @escaping @Sendable () -> (url: String?, data: Data?)
    ) async -> (image: NSImage, origin: Origin, url: String?)? {
        let key = track.coverKey
        let playerOnly = track.coverFromPlayerOnly
        if let image = memory[key] { return (image, .memory, nil) }
        if !playerOnly, let data = Self.readDisk(key), let image = NSImage(data: data) {
            memory[key] = image
            return (image, .disk, nil)
        }

        // The player. Right after a change its URL can be the old one.
        var playerURL: String?
        for attempt in 0..<5 {
            let answer = await Task.detached(priority: .userInitiated) { readPlayer() }.value
            if let data = answer.data, let image = NSImage(data: data), Self.isUsable(image) {
                if playerOnly {
                    // A page's icon is not a song's: kept for this session only.
                    memory[key] = image
                } else {
                    store(data, image, for: key)
                }
                return (image, .player, nil)
            }
            guard let url = answer.url else { break }
            if isStale(url, for: key, previousURL: previousURL) {
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    continue
                }
                Log.line("cover: the player still gives the previous song's cover; searching the catalogues")
                break
            }
            playerURL = url
            if let (data, image) = await download(url) {
                remember(url: url, for: key)
                if playerOnly { memory[key] = image } else { store(data, image, for: key) }
                return (image, .player, url)
            }
            break
        }

        // A page in the browser, or the DJ talking, has no album in any catalogue.
        guard !playerOnly else { return nil }

        // The catalogues.
        if let (data, image, origin) = await onlineCover(title: track.title, artist: track.artist) {
            store(data, image, for: key)
            return (image, origin, playerURL)
        }
        return nil
    }

    /// Notes that a player URL belongs to a song. `ThemeEngine` also calls it a few
    /// seconds into a song whose cover came from the cache, so the next song can
    /// tell the old URL from its own.
    func remember(url: String, for key: String) {
        if urlOwner.count > 400 { urlOwner.removeAll() }
        urlOwner[url] = key
    }

    /// Whether a URL is the previous song's and not this one's.
    func isStale(_ url: String, for key: String, previousURL: String?) -> Bool {
        if url == previousURL { return true }
        if let owner = urlOwner[url], owner != key { return true }
        return false
    }

    /// Forgets every cover, in memory and on disk. The settings offer it, for a
    /// cover that was saved wrong.
    func clearCache() {
        memory.removeAll()
        urlOwner.removeAll()
        if let folder = Self.folder() { try? FileManager.default.removeItem(at: folder) }
        Log.line("cover: cache cleared")
    }

    /// Looks the cover up in the catalogues only. Also what the bench measures.
    func onlineCover(title: String, artist: String) async -> (Data, NSImage, Origin)? {
        let cleanTitle = NetEase.cleanedTitle(title)
        let cleanArtist = NetEase.primaryArtist(artist)
        guard !cleanTitle.isEmpty else { return nil }

        // Deezer first: it tolerates being asked often, and its plain search finds
        // the songs with accents and other alphabets that the structured one misses.
        // The Apple catalogue answers 403 or 429 when it is asked in bursts.
        if let url = await deezerCover(title: cleanTitle, artist: cleanArtist),
           let (data, image) = await download(url) {
            return (data, image, .deezer)
        }
        if let url = await itunesCover(title: cleanTitle, artist: cleanArtist),
           let (data, image) = await download(url) {
            return (data, image, .itunes)
        }
        return nil
    }

    // MARK: - Catalogues

    private func itunesCover(title: String, artist: String) async -> String? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(title) \(artist)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return nil }

        let wantTitle = LRCLib.normalise(title)
        let wantArtist = LRCLib.normalise(artist)
        for result in results {
            let gotTitle = LRCLib.normalise(NetEase.cleanedTitle(result["trackName"] as? String ?? ""))
            let gotArtist = LRCLib.normalise(result["artistName"] as? String ?? "")
            guard gotTitle == wantTitle,
                  wantArtist.isEmpty || gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist),
                  let small = result["artworkUrl100"] as? String
            else { continue }
            // The catalogue serves any size: ask for a big one.
            return small.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")
        }
        return nil
    }

    private func deezerCover(title: String, artist: String) async -> String? {
        var components = URLComponents(string: "https://api.deezer.com/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(title) \(artist)"),
            URLQueryItem(name: "limit", value: "12"),
        ]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["data"] as? [[String: Any]]
        else { return nil }

        let wantTitle = LRCLib.normalise(title)
        let wantArtist = LRCLib.normalise(artist)
        // A different recording of the same song is not the cover of this one.
        let variants = ["live", "karaoke", "instrumental", "remix", "cover", "sped", "slowed", "tribute", "8bit"]
        let rawTitle = title.lowercased()

        var best: (score: Int, cover: String)?
        for result in results {
            let name = result["title"] as? String ?? ""
            let gotTitle = LRCLib.normalise(NetEase.cleanedTitle(name))
            let artistName = (result["artist"] as? [String: Any])?["name"] as? String ?? ""
            let gotArtist = LRCLib.normalise(artistName)
            let album = result["album"] as? [String: Any]
            guard let cover = album?["cover_xl"] as? String ?? album?["cover_big"] as? String,
                  !gotTitle.isEmpty
            else { continue }

            // The artist has to be the right one.
            guard wantArtist.isEmpty || gotArtist.contains(wantArtist) || wantArtist.contains(gotArtist)
            else { continue }

            var score = 0
            if gotTitle == wantTitle { score += 100 }
            else if gotTitle.contains(wantTitle) || wantTitle.contains(gotTitle) { score += 40 }
            else { continue }
            // Shorter titles are closer to the one asked for.
            score -= abs(gotTitle.count - wantTitle.count)

            let lowerName = name.lowercased()
            for variant in variants where lowerName.contains(variant) && !rawTitle.contains(variant) {
                score -= 60
            }
            if best == nil || score > best!.score { best = (score, cover) }
        }
        // Below zero is a wrong recording of the right song or worse: no cover.
        guard let best, best.score > 0 else { return nil }
        return best.cover
    }

    // MARK: - Downloading

    private func download(_ urlString: String) async -> (Data, NSImage)? {
        guard let url = URL(string: urlString),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), Self.isUsable(image)
        else { return nil }
        return (data, image)
    }

    /// A cover is a real picture, not the 1-pixel placeholder some services answer.
    private static func isUsable(_ image: NSImage) -> Bool {
        let size = image.size
        return size.width >= 64 && size.height >= 64
    }

    // MARK: - Disk cache

    private func store(_ data: Data, _ image: NSImage, for key: String) {
        memory[key] = image
        Self.writeDisk(data, for: key)
    }

    /// `Covers2`: the folder of the first versions (`Covers`) could hold covers saved
    /// with the previous song's URL, so it is dropped once and the covers are found again.
    private static func folder() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let old = caches.appendingPathComponent("MycSs/Covers", isDirectory: true)
        if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.removeItem(at: old) }
        let folder = caches.appendingPathComponent("MycSs/Covers2", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func file(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder()?.appendingPathComponent(String(digest.prefix(40)))
    }

    private static func readDisk(_ key: String) -> Data? {
        guard let file = file(for: key) else { return nil }
        return try? Data(contentsOf: file)
    }

    private static func writeDisk(_ data: Data, for key: String) {
        guard let file = file(for: key) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
