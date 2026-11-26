import Foundation

/// What the system says is playing, and who plays it (spec 014, ADR 008).
///
/// The browsers that cannot be scripted (Firefox, Zen and their kin) publish what
/// they play to macOS's Now Playing, like every media app. MediaRemote is closed to
/// third parties since macOS 15.4, so a small library of ours
/// (`Support/NowPlayingAdapter/adapter.m`) is loaded by `/usr/bin/perl`, a system
/// binary that is still allowed, and talks to MediaRemote from inside it. It prints
/// one JSON line every 300 ms and takes commands on its standard input.
///
/// The process only runs while something needs it (a Firefox-family browser is open
/// and the browser reading is on), and ends with the app: when MycSs closes its pipe
/// the library exits.
final class SystemNowPlaying {

    static let shared = SystemNowPlaying()

    struct State: Equatable {
        var bundleID: String
        var isPlaying: Bool
        var title: String
        var artist: String
        var album: String
        var elapsed: TimeInterval
        var duration: TimeInterval
        var rate: Double
        /// The moment `elapsed` was true.
        var timestamp: Date

        /// Where the playhead is now.
        var position: TimeInterval {
            guard isPlaying else { return elapsed }
            return elapsed + max(Date().timeIntervalSince(timestamp), 0) * (rate > 0 ? rate : 1)
        }
    }

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var latestState: State?
    private var lastLine = Date.distantPast
    /// Set when the library cannot be found or MediaRemote is gone.
    private(set) var failure: String?

    /// The self test puts a reading here to drive what reads from this one.
    var injected: State?

    /// The last reading, or nil when the process is not running or has gone quiet.
    var latest: State? {
        lock.lock(); defer { lock.unlock() }
        if let injected { return injected }
        guard process?.isRunning == true, Date().timeIntervalSince(lastLine) < 3 else { return nil }
        return latestState
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        if process?.isRunning == true { lock.unlock(); return }
        lock.unlock()

        guard let library = Self.libraryURL() else {
            if failure == nil {
                failure = "library not found"
                Log.warn("nowplaying: the adapter library was not found (Resources/libMycSsNowPlaying.dylib)")
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.perlLoader, library.path]
        let output = Pipe(), inputPipe = Pipe()
        process.standardOutput = output
        process.standardInput = inputPipe
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.received(data)
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            self?.ended()
        }
        do {
            try process.run()
        } catch {
            failure = "could not start perl"
            Log.warn("nowplaying: could not start /usr/bin/perl: \(error.localizedDescription)")
            return
        }
        lock.lock()
        self.process = process
        self.input = inputPipe.fileHandleForWriting
        buffer = Data()
        latestState = nil
        lock.unlock()
        failure = nil
        Log.line("nowplaying: reading the system's Now Playing")
    }

    func stop() {
        lock.lock()
        let process = self.process
        let input = self.input
        self.process = nil
        self.input = nil
        latestState = nil
        lock.unlock()
        // Closing the input is how the library knows to end.
        try? input?.close()
        process?.terminate()
        if process != nil { Log.line("nowplaying: stopped") }
    }

    private func ended() {
        lock.lock()
        process = nil
        input = nil
        lock.unlock()
    }

    // MARK: - Reading

    private func received(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let state = Self.parse(Data(line)) {
                latestState = state
                lastLine = Date()
            } else if String(decoding: line, as: UTF8.self).contains("unavailable") {
                failure = "MediaRemote is not available"
            }
        }
    }

    /// One line of the library.
    static func parse(_ line: Data) -> State? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["error"] == nil
        else { return nil }
        func number(_ key: String) -> Double {
            let raw = (object[key] as? NSNumber)?.doubleValue ?? 0
            return raw.isFinite ? raw : 0
        }
        let stamp = number("ts")
        return State(
            bundleID: object["b"] as? String ?? "",
            isPlaying: object["p"] as? Bool ?? false,
            title: (object["ti"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            artist: (object["ar"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            album: (object["al"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            elapsed: max(number("t"), 0),
            duration: max(number("d"), 0),
            rate: number("r"),
            timestamp: stamp > 0 ? Date(timeIntervalSince1970: stamp) : Date()
        )
    }

    // MARK: - Commands

    /// Sends a command to whichever app the system says is playing.
    func send(_ command: PlayerCommand) {
        let line: String
        switch command {
        case .playPause: line = "toggle"
        case .next: line = "next"
        case .previous: line = "previous"
        case .seek(let seconds): line = String(format: "seek %.2f", max(0, seconds))
        }
        lock.lock()
        let input = self.input
        lock.unlock()
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    // MARK: - The library

    /// Loads the library into perl and runs its stream. Exit codes tell what failed.
    static let perlLoader = """
    use DynaLoader;
    my $handle = DynaLoader::dl_load_file($ARGV[0], 0) or exit 2;
    my $symbol = DynaLoader::dl_find_symbol($handle, "adapter_stream") or exit 3;
    my $run = DynaLoader::dl_install_xsub("main::run", $symbol);
    &$run("main");
    """

    /// The library: inside the app; or, while developing, one built from the source in
    /// the repository (the app is not there when MycSs runs from `.build`).
    static func libraryURL() -> URL? {
        let manager = FileManager.default
        if let path = ProcessInfo.processInfo.environment["MYCSS_NOWPLAYING_DYLIB"], manager.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("libMycSsNowPlaying.dylib"),
           manager.fileExists(atPath: bundled.path) {
            return bundled
        }
        // `#filePath` is where this file was compiled: .../Sources/MycSs/Player/.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Support/NowPlayingAdapter/adapter.m")
        guard manager.fileExists(atPath: source.path), manager.fileExists(atPath: "/usr/bin/clang") else { return nil }
        let folder = manager.temporaryDirectory.appendingPathComponent("mycss-nowplaying-\(getuid())", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let built = folder.appendingPathComponent("libMycSsNowPlaying.dylib")
        let builtDate = (try? manager.attributesOfItem(atPath: built.path)[.modificationDate] as? Date) ?? .distantPast
        let sourceDate = (try? manager.attributesOfItem(atPath: source.path)[.modificationDate] as? Date) ?? .distantFuture
        if builtDate > sourceDate { return built }
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compile.arguments = ["-dynamiclib", "-fobjc-arc", "-framework", "Foundation", source.path, "-o", built.path]
        compile.standardError = FileHandle.nullDevice
        try? compile.run()
        compile.waitUntilExit()
        return compile.terminationStatus == 0 ? built : nil
    }
}
