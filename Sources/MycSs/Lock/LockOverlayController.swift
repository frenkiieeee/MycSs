import AppKit
import SwiftUI

/// Creates one overlay panel per display and shows or hides them according to the
/// lock state.
///
/// The overlay only exists while the screen is locked. When the Mac is unlocked the
/// panels are torn down entirely, which also means Spotify polling stops entirely
/// (see `SyncEngine`).
@MainActor
final class LockOverlayController {

    private var panels: [CGDirectDisplayID: LockOverlayPanel] = [:]
    private let lockState: LockState
    private let model = LyricsViewModel()

    /// The model the notch shares with the overlay.
    var sharedModel: LyricsViewModel { model }

    /// Whether the lock screen, the screensaver or the preview is on screen.
    ///
    /// **It is a flag, not `NSWindow.isVisible`.** The lock panels are moved into
    /// every new system Space (the volume indicator, the screenshot tool and
    /// others create one) and "presented again" there, which leaves the window
    /// marked as visible while nothing is on screen. Asking the window made the
    /// notch hide itself every time the volume changed or a screenshot was taken.
    var isOverlayVisible: Bool {
        overlayShown || isPresenting
    }

    /// Set only by `show`, `showPreviewWindow` and `hide`.
    private var overlayShown = false

    var isScreenLocked: Bool { lockState.isLocked }

    /// True while the overlay is waiting for the lock screen's Space.
    private var waitingForLockScreen = false

    /// When the lock happened, used to give up waiting and show anyway.
    private var lockedAt: Date?

    /// How long to wait for the lock screen's Space before showing the overlay
    /// regardless.
    ///
    /// The Space lookup is the correct trigger, but it is an implementation
    /// detail of the window server. If something changes and the Space cannot be
    /// found, the overlay must still appear — a late overlay is much better than
    /// no overlay at all.
    private let lockScreenTimeout: TimeInterval = 1.2

    init(lockState: LockState) {
        self.lockState = lockState
        model.onDismissRequest = { [weak self] in
            self?.dismissFromOverlay()
        }
    }

    /// Whether the user closed the overlay on this lock, to see the real lock
    /// screen. It stays closed until the next lock.
    private var dismissedWhileLocked = false

    /// Escape, or a click outside the lyrics.
    private func dismissFromOverlay() {
        if isPresenting {
            hidePresentation()
        } else if lockState.isLocked, !dismissedWhileLocked {
            Log.line("overlay: closed by the user on the lock screen")
            dismissedWhileLocked = true
            hide()
        }
    }

    /// Starts the continuous Spotify polling.
    func startListening() {
        model.startListening()
    }

    func start() {
        // The private API is opened up front, so the first lock does not have
        // to wait for it, and the spaces of the session are written down, so
        // that the Space the lock creates can be told apart from the
        // leftovers of the previous one.
        SkyLight.shared.prepare()
        SkyLight.shared.rememberSpaces()

        // The window is made now, and hidden, instead of being made at the
        // moment of the lock.
        //
        // A window that is created while the screen is locking is not drawn
        // in the Space it is moved to: it stays invisible until the screen is
        // locked a second time, when the window already exists and the
        // compositor draws it without trouble.
        rebuild()
        for panel in panels.values {
            panel.orderOut(nil)
        }

        lockState.onChange = { [weak self] locked in
            guard let self else { return }
            self.handleLockChange(locked)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    private func handleLockChange(_ locked: Bool) {
        if locked {
            // The lock takes over from the screensaver.
            hidePresentation()
            dismissedWhileLocked = false
            // Show the overlay immediately rather than waiting for the next
            // tick: the lock notification is the earliest signal there is, and
            // every millisecond of delay is visible on screen.
            //
            // The window is placed in the best known lock Space right away, and
            // `followLockScreen` moves it again as soon as the lock screen
            // creates its own Space.
            waitingForLockScreen = false
            lockedAt = Date()
            lockedAtTimestamp = Date().timeIntervalSince1970
            Log.line("overlay: locked, showing overlay")
            Log.line("skylight: spaces at lock \(SkyLight.shared.describeSpaces())")
            show()

            // A moment later, when the lock screen is already up, the state of
            // the window says whether it is really on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let panel = self?.panels.values.first else { return }
                Log.line("skylight: window state \(SkyLight.shared.describe(panel))")
            }
        } else {
            waitingForLockScreen = false
            lockedAt = nil
            hide()
            // The windows of the lock screen are written down again, so that
            // the next lock can tell which one is the field of the password.
                // The spaces of the unlocked session, so that the Space the lock
            // creates can be told apart from the leftovers of the last one.
            SkyLight.shared.rememberSpaces()
        }
    }

    /// When the lock was detected, for measuring how long the overlay takes to
    /// appear.
    private var lockedAtTimestamp: TimeInterval = 0

    /// Measures how long the overlay takes to reach the lock screen's Space.
    ///
    /// The first move happens immediately when the lock is detected, and the
    /// second one when the lock screen creates its Space. The difference is the
    /// delay the user actually sees.
    private func measureAppearance() {
        guard lockedAtTimestamp > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - lockedAtTimestamp
        lockedAtTimestamp = 0
        Log.line(String(format: "overlay: reached the lock screen space in %.0f ms", elapsed * 1000))
    }

    /// Keeps the overlay in step with the lock screen.
    ///
    /// The lock screen creates its Space a fraction of a second after the lock
    /// notification, so the overlay is placed in the best known Space first and
    /// moved again as soon as the real one appears.
    func tick() {
        followLockScreen()
        presentationTick()
    }

    /// Moves the overlay again if the lock screen has created a newer Space.
    ///
    /// The lock screen's Space is created a fraction of a second after the lock
    /// notification, so the overlay is placed in the newest known lock Space and
    /// then moved again as soon as the real one appears.
    func followLockScreen() {
        guard !isPreview, !dismissedWhileLocked else { return }

        var moved = false
        for panel in panels.values {
            if SkyLight.shared.followLockScreenSpace(of: panel) { moved = true }
        }
        if moved { measureAppearance() }

        // The spaces are written to the log when they change: they are what
        // tells the lock screen's space apart from the others, and the first
        // lock after the app starts is the one that does not work.
        ticks += 1
        if ticks % 12 == 0 {
            let spaces = SkyLight.shared.describeSpaces()
            if spaces != lastSpaces {
                lastSpaces = spaces
                Log.line("skylight: spaces \(spaces)")
            }
        }
    }

    /// The number of ticks since the last log line.
    private var ticks = 0
    /// The spaces as they were the last time they were written to the log.
    private var lastSpaces = ""

    /// Shows the overlay without the screen being locked.
    ///
    /// This is a development aid, not a user-facing feature: it lets the layout
    /// be iterated on without locking the Mac every time.
    func showPreview() {
        Log.line("overlay: preview requested")
        showPreviewWindow()
    }

    func hidePreview() {
        Log.line("overlay: preview hidden")
        hide()
    }

    /// Forces the password hint to be visible, for checking the reveal without
    /// moving the mouse.
    func forceHint() {
        model.forceHint()
        Log.line("overlay: hint forced for the snapshot")
    }

    // MARK: - Screensaver

    /// Whether the lyrics are on screen as a screensaver.
    private(set) var isPresenting = false
    private var presentedAt: Date?
    private var lastIdleCheck: Date = .distantPast
    private var idleCheckInFlight = false

    /// How long after showing the screensaver an input event is ignored, so the
    /// key press that opened it does not close it again.
    private let presentationGrace: TimeInterval = 1.2

    func togglePresentation() {
        if isPresenting { hidePresentation() } else { showPresentation() }
    }

    /// Whether the screensaver opened by itself after the idle time. Only then
    /// does any key or movement close it, like a real screensaver; when it was
    /// opened on purpose, the mouse has to be free to use the player controls.
    private var presentedByIdle = false

    /// The panels of the screensaver. They are **not** the panels of the lock
    /// screen: those are moved into the lock screen's Space with private calls,
    /// and a window that has been through a different level, a different Space
    /// behaviour and a different mouse behaviour does not always come back from
    /// it. After using the screensaver, the lock screen stopped showing the
    /// overlay. So the lock panels are never touched, and these are made when the
    /// screensaver opens and thrown away when it closes.
    private var presentationPanels: [CGDirectDisplayID: LockOverlayPanel] = [:]

    /// Shows the lyrics over the desktop, like a screensaver.
    ///
    /// It uses the same view as the lock screen, in a window that covers
    /// everything. It does not read the keyboard beyond Escape.
    func showPresentation(byIdle: Bool = false) {
        guard !lockState.isLocked, !isPresenting else { return }
        isPresenting = true
        presentedByIdle = byIdle
        presentedAt = Date()

        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let panel = makePanel(displayID: id)
            panel.joinsAllSpaces = false
            panel.isPresentation = true
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            presentationPanels[id] = panel
        }
        Log.line("overlay: screensaver shown on \(presentationPanels.count) display(s)")
        // No password to type here, so the keyboard is not watched.
        model.start(mode: .presentation)
        model.setVisible(true)
        DisplayPower.apply(AppSettings.shared.powerMode)
    }

    func hidePresentation() {
        guard isPresenting else { return }
        isPresenting = false
        presentedAt = nil
        for panel in presentationPanels.values { panel.orderOut(nil) }
        presentationPanels.removeAll()
        model.stop()
        model.setVisible(false)
        DisplayPower.release()
        Log.line("overlay: screensaver closed")
    }

    /// Seconds since the last key press, click or mouse movement.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    /// Closes the screensaver when the user is back, and opens it after the
    /// configured idle time.
    private func presentationTick() {
        let now = Date()

        if isPresenting {
            guard presentedByIdle,
                  let presentedAt, now.timeIntervalSince(presentedAt) > presentationGrace
            else { return }
            if Self.idleSeconds() < 0.3 { hidePresentation() }
            return
        }

        // The idle check runs about once a second, not on every tick.
        guard now.timeIntervalSince(lastIdleCheck) > 1 else { return }
        lastIdleCheck = now

        let minutes = AppSettings.shared.idleMinutes
        let threshold = Double(minutes) * 60
        guard minutes > 0, !idleCheckInFlight, !lockState.isLocked,
              !overlayShown,
              Self.idleSeconds() >= threshold
        else { return }

        idleCheckInFlight = true
        Task { [weak self] in
            guard let self else { return }
            let playing = await self.model.isMusicPlaying()
            self.idleCheckInFlight = false
            if playing, Self.idleSeconds() >= threshold { self.showPresentation(byIdle: true) }
        }
    }

    // MARK: - Panels

    private func rebuild() {
        let wanted = NSScreen.screens.reduce(into: [CGDirectDisplayID: NSScreen]()) { acc, screen in
            if let id = screen.displayID { acc[id] = screen }
        }

        for (id, panel) in panels where wanted[id] == nil {
            panel.orderOut(nil)
            panels[id] = nil
        }

        for (id, screen) in wanted {
            let panel = panels[id] ?? makePanel(displayID: id)
            panels[id] = panel
            panel.setFrame(screen.frame, display: true)
        }
    }

    private func makePanel(displayID: CGDirectDisplayID) -> LockOverlayPanel {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = LockOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: OverlayRootView(model: model, displayID: displayID))
        // The hosting view is created with a zero frame. Without an explicit one
        // it stays zero-sized and the panel renders nothing at all — the window is
        // on screen but its content is invisible.
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        return panel
    }

    /// Whether the panels behave as a lock screen overlay (joining every Space)
    /// or as an ordinary window (the preview).
    private var isPreview = false

    private func show() {
        overlayShown = true
        isPreview = false
        rebuild()
        let shown = Date()
        for panel in panels.values {
            panel.joinsAllSpaces = true
            // `orderFrontRegardless` so the panel is shown even though this app is
            // not the active application (it never becomes active).
            panel.orderFrontRegardless()
            // The window number only exists once the panel is on screen, so the
            // elevation has to happen after ordering it front.
            SkyLight.shared.elevate(panel)
        }
        // How long the overlay itself took to appear, before it was even moved
        // into the lock screen's Space.
        Log.line(String(
            format: "overlay: shown on %d display(s) in %.0f ms",
            panels.count, shown.timeIntervalSince(lockedAt ?? shown) * 1000
        ))
        model.start(mode: .lock)
        model.setVisible(true)
        Log.line("overlay: lock screen content: track '\(model.track.title)', \(model.lyrics?.lines.count ?? 0) lyric lines, lyrics not found: \(model.lyricsNotFound)")
        // Keep the display awake so the lyrics stay visible.
        DisplayPower.apply(AppSettings.shared.powerMode)
    }

    /// Shows the overlay as an ordinary window, without touching the Spaces.
    ///
    /// This is what the preview uses. It deliberately does **not** go through
    /// `SkyLightOperator`: moving the window into the lock screen's Space takes it
    /// off the current Space, which makes the preview invisible and drags the Dock
    /// along with it. The preview is for looking at the layout on the desktop, so
    /// it stays a plain window.
    private func showPreviewWindow() {
        overlayShown = true
        isPreview = true
        rebuild()
        for panel in panels.values {
            panel.joinsAllSpaces = false
            panel.orderFrontRegardless()
        }
        Log.line("overlay: preview shown on \(panels.count) display(s)")
        model.start(mode: .preview)
        model.setVisible(true)
    }

    private func hide() {
        overlayShown = false
        for panel in panels.values {
            panel.orderOut(nil)
        }
        model.stop()
        model.setVisible(false)
        DisplayPower.release()
        Log.line("overlay: hidden")
    }

    // MARK: - Debug snapshot

    /// Renders the overlay to a PNG.
    ///
    /// The window that is on screen is the real thing, so it is captured first.
    /// But that window lives in the lock screen's Space, and the window server
    /// does not draw a window that belongs to another Space, so the capture
    /// comes out empty while the screen is locked. In that case the picture is
    /// rendered from the view itself instead, which produces the same pixels
    /// without needing Screen Recording permission.
    func snapshot(to path: String) {
        // `MYCSS_SNAPSHOT=view` skips the window capture: on recent macOS the
        // window capture comes out as a white image, which is not blank, so
        // the fallback never kicks in.
        let viewOnly = ProcessInfo.processInfo.environment["MYCSS_SNAPSHOT"] == "view"
        let data = (viewOnly ? nil : captureWindow()) ?? captureView()

        guard let data else {
            Log.error("snapshot: the image could not be rendered")
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: path))
            Log.line("snapshot: written to \(path)")
        } catch {
            Log.error("snapshot: \(error.localizedDescription)")
        }
    }

    /// Captures the window that is on screen.
    ///
    /// Returns nil when the window is not being drawn, which is what happens
    /// when it belongs to another Space.
    private func captureWindow() -> Data? {
        guard let panel = presentationPanels.values.first ?? panels.values.first,
              let view = panel.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }

        view.cacheDisplay(in: view.bounds, to: representation)
        guard !isBlank(representation) else {
            Log.line("snapshot: the window is in another space, rendering the view instead")
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    /// Renders the view on its own.
    private func captureView() -> Data? {
        let size = panels.values.first?.frame.size
            ?? NSScreen.main?.frame.size
            ?? CGSize(width: 1440, height: 900)

        // A dark base: the view is mostly white text, which cannot be seen on the
        // transparent background of an image.
        let renderer = ImageRenderer(content: ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.1)
            OverlayRootView(model: model)
        })
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }

        return bitmap.representation(using: .png, properties: [:])
    }

    /// Whether a bitmap is completely empty.
    ///
    /// A window that is not drawn produces a bitmap where every pixel is
    /// transparent.
    private func isBlank(_ representation: NSBitmapImageRep) -> Bool {
        guard let image = representation.cgImage else { return true }

        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.allSatisfy { $0 == 0 }
    }


    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}

extension NSScreen {
    /// The CoreGraphics id of the display.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
