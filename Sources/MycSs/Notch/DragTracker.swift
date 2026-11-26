import AppKit

/// Tells a real drag of files from a drag pasteboard left over from an older one
/// (spec 013).
///
/// The system's drag pasteboard keeps its files after a drag ends, so "the button is
/// down and the pasteboard has files" was true for any click and hold (selecting
/// text, moving a window) after the first drag of the session, and the shelf opened
/// by itself. A drag is real only when the pasteboard changed **after** the button
/// went down: its change count is noted at every press, by a global monitor of
/// clicks (it reads no keys and needs no permission) and, as a fallback, on the
/// first tick that sees the button down.
@MainActor
final class DragTracker {

    // Injected by the self test; the system's by default.
    var pasteboardCount: () -> Int = { NSPasteboard(name: .drag).changeCount }
    var buttonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var hasFiles: () -> Bool = {
        NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// The last answer of `update()`.
    private(set) var isDragging = false

    private var countAtPress: Int?
    private var wasDown = false
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pressed() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.pressed()
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        countAtPress = nil
        wasDown = false
        isDragging = false
    }

    /// A press of the button: what the pasteboard holds now is old.
    func pressed() {
        countAtPress = pasteboardCount()
        wasDown = true
    }

    /// Called on every tick: whether files are being dragged right now.
    @discardableResult
    func update() -> Bool {
        guard buttonDown() else {
            wasDown = false
            countAtPress = nil
            isDragging = false
            return false
        }
        if !wasDown {
            wasDown = true
            if countAtPress == nil { countAtPress = pasteboardCount() }
        }
        guard let start = countAtPress else {
            isDragging = false
            return false
        }
        isDragging = pasteboardCount() != start && hasFiles()
        return isDragging
    }
}
