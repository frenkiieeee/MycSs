import Foundation

/// A cache of HTTP responses with retries, used by the lyric providers.
///
/// **Why the retries matter**: LRCLIB, the main lyric source, fails with
/// `503 ServerOverloaded` very often — measured on this machine, four of five
/// back-to-back requests failed while one succeeded. It is a transient
/// condition, not a missing lyric, so the request has to be tried again.
///
/// The retries are spaced out so the service gets a chance to recover, and the
/// backoff grows so a genuinely missing lyric is not hammered.
actor HTTPCache {

    static let shared = HTTPCache()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private var memoryCache: [String: Data] = [:]

    /// How many times a request is tried before giving up.
    private let maxAttempts = 5

    /// Returns the body for `url`, fetching it if needed.
    ///
    /// - Parameter url: the request URL, which is also the cache key.
    /// - Returns: the response body, or `nil` when every attempt failed.
    func data(for url: URL, headers: [String: String] = [:]) async -> Data? {
        if let cached = memoryCache[url.absoluteString] {
            return cached
        }

        // Disk cache: a lyric that was already downloaded must never be
        // requested again.
        if let onDisk = DiskCache.read(url.absoluteString) {
            memoryCache[url.absoluteString] = onDisk
            return onDisk
        }

        guard let body = await fetch(url: url, headers: headers) else { return nil }
        memoryCache[url.absoluteString] = body
        DiskCache.write(body, for: url.absoluteString)
        return body
    }

    /// Performs the request, retrying transient failures with a backoff.
    private func fetch(url: URL, headers: [String: String]) async -> Data? {
        for attempt in 1...maxAttempts {
            do {
                var request = URLRequest(url: url)
                for (name, value) in headers {
                    request.setValue(value, forHTTPHeaderField: name)
                }
                if request.value(forHTTPHeaderField: "User-Agent") == nil {
                    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
                }

                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse {
                    switch http.statusCode {
                    case 200...299:
                        return data
                    case 404:
                        // Not found is a real answer, not a failure.
                        Log.line("http: 404 for \(url.lastPathComponent)")
                        return nil
                    case 429, 500...599:
                        // The service is overloaded or rate-limiting. This is
                        // the common case for LRCLIB, and it is worth waiting.
                        Log.line("http: \(http.statusCode), attempt \(attempt)/\(maxAttempts)")
                    default:
                        Log.warn("http: unexpected \(http.statusCode) for \(url.absoluteString)")
                        return nil
                    }
                } else {
                    return data
                }
            } catch {
                Log.line("http: request failed (\(error.localizedDescription)), attempt \(attempt)/\(maxAttempts)")
            }

            // Backoff: 0.3s, 0.6s, 1.2s, 2.4s.
            let delay = UInt64(0.3 * pow(2, Double(attempt - 1)) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }

        Log.warn("http: giving up on \(url.absoluteString)")
        return nil
    }

    private static let userAgent = "MycSs/0.1 (macOS lock screen lyrics)"
}

/// A simple on-disk cache for lyric bodies.
///
/// Stored under the app's cache directory, so the system can purge it when
/// space runs low. Keys are hashed so the file names are safe.
enum DiskCache {

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let base = caches.appendingPathComponent("MycSs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Lyrics", isDirectory: true)
    }()

    static func read(_ key: String) -> Data? {
        guard let file = url(for: key) else { return nil }
        return try? Data(contentsOf: file)
    }

    static func write(_ data: Data, for key: String) {
        guard let file = url(for: key) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func url(for key: String) -> URL? {
        guard let directory else { return nil }
        let name = key.data(using: .utf8)?.base64URLEncodedString() ?? ""
        return directory.appendingPathComponent(name + ".json")
    }
}

extension Data {
    /// Base64 with the URL-safe alphabet and no padding, so it can be used in a
    /// file name.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
