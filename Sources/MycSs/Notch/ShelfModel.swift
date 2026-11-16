import AppKit
import Observation

/// One file on the shelf.
struct ShelfItem: Identifiable, Equatable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// A shelf for files: drop them on the notch to keep them at hand, drag them out
/// to wherever they are needed, or send them with AirDrop.
///
/// Only the paths are kept (in the preferences), never the files: the shelf does
/// not copy anything, and a file that has moved or been deleted drops out of it.
@MainActor
@Observable
final class ShelfModel {

    private(set) var items: [ShelfItem] = []

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let key = "shelfPaths"

    init() {
        load()
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Opens the AirDrop sheet with everything on the shelf.
    func sendWithAirDrop() {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    // MARK: - Storage

    private func load() {
        let paths = defaults.stringArray(forKey: key) ?? []
        items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }

    private func save() {
        defaults.set(items.map(\.url.path), forKey: key)
    }
}
