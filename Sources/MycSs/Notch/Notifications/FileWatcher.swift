import Foundation

/// Tells, at once, when one of a few files or folders is written to (spec 012).
///
/// SQLite writes a new notification into `db-wal` (or into `db` itself without a
/// write-ahead log), and the system reports that write to a `DispatchSource` as it
/// happens. A file that is deleted or renamed (the log is replaced after a
/// checkpoint) is watched again a moment later. Several writes in a row are told
/// once.
@MainActor
final class FileWatcher {

    /// Called on the main thread after a write.
    var onChange: (() -> Void)?

    private var paths: [String] = []
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending = false
    private var rewatchPending = false

    var isWatching: Bool { !sources.isEmpty }

    func watch(_ paths: [String]) {
        stop()
        self.paths = paths
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .delete, .rename, .link],
                queue: .main
            )
            source.setEventHandler { [weak self, weak source] in
                let events = source?.data ?? []
                MainActor.assumeIsolated { self?.fired(events) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func fired(_ events: DispatchSource.FileSystemEvent) {
        if events.contains(.delete) || events.contains(.rename), !rewatchPending {
            rewatchPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rewatchPending = false
                    self.watch(self.paths)
                }
            }
        }
        guard !pending else { return }
        pending = true
        // A short wait gathers the writes of one transaction into one reading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.onChange?()
            }
        }
    }
}
