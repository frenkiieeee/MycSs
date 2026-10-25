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

    /// Baseline Space id captured at launch.
    ///
    /// The lock screen gets a brand new Space on every lock. If the overlay were
    /// shown immediately on the lock notification, it could land in the *previous*
    /// lock's Space and render underneath the incoming lock screen. Waiting for a
    /// Space newer than this baseline avoids that race.
    private var baselineSpaceID: UInt64 = 0
    private var waitingForFreshSpace = false

    /// When the lock happened, used to decide when to stop waiting for a fresh
    /// Space and fall back to showing the overlay anyway.
    private var lockedAt: Date?

    /// How long to wait for the lock screen's own Space before showing the overlay
    /// regardless.
    ///
    /// The fresh-Space signal is the most correct trigger, but it is an
    /// implementation detail of the window server. If a macOS version stops
    /// creating a new Space per lock, waiting forever would mean the overlay
    /// never appears. Two seconds is long enough for the lock screen to come up
    /// and short enough that the user does not notice the difference.
    private let freshSpaceTimeout: TimeInterval = 2.0

    init(lockState: LockState) {
        self.lockState = lockState
    }

    func start() {
        // Capture the newest lock Space that already exists (if any). The next lock
        // will create a newer one, and that is the signal that the real lock
        // screen is up.
        baselineSpaceID = SkyLight.shared.newestLockSpace() ?? 0
        Log.line("overlay: baseline lock space id = \(baselineSpaceID)")

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
            // Do not show the overlay yet: the incoming lock screen's Space has
            // to be created first.
            waitingForFreshSpace = true
            lockedAt = Date()
            Log.line("overlay: waiting for fresh lock space")
        } else {
            waitingForFreshSpace = false
            lockedAt = nil
            hide()
        }
    }

    /// Called from the run loop while locked, to show the overlay once the lock
    /// screen's Space exists.
    func tick() {
        guard waitingForFreshSpace else { return }

        // The user can turn the overlay off entirely.
        guard AppSettings.shared.overlayEnabled else {
            waitingForFreshSpace = false
            lockedAt = nil
            Log.line("overlay: disabled in settings, not showing")
            return
        }

        let current = SkyLight.shared.newestLockSpace() ?? 0
        if current != 0, current > baselineSpaceID {
            // The lock screen created its own Space: this is the reliable signal.
            waitingForFreshSpace = false
            lockedAt = nil
            baselineSpaceID = current
            Log.line("overlay: fresh lock space \(current) detected, showing overlay")
            show()
            return
        }

        // Fallback: the window server did not create a new Space. Waiting forever
        // would mean the overlay never appears, so show it anyway after a short
        // grace period and let SkyLightOperator's own Space handle the level.
        if let lockedAt, Date().timeIntervalSince(lockedAt) > freshSpaceTimeout {
            waitingForFreshSpace = false
            self.lockedAt = nil
            Log.line("overlay: no fresh space after \(freshSpaceTimeout)s, showing anyway")
            show()
        }
    }

    /// Shows the overlay without the screen being locked.
    ///
    /// This is a development aid, not a user-facing feature: it lets the layout
    /// be iterated on without locking the Mac every time. The window is elevated
    /// to the newest lock Space so the rendering path is the same one the real
    /// overlay takes.
    func showPreview() {
        Log.line("overlay: preview requested")
        show()
    }

    func hidePreview() {
        Log.line("overlay: preview hidden")
        hide()
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
            let panel = panels[id] ?? makePanel()
            panels[id] = panel
            panel.setFrame(screen.frame, display: true)
        }
    }

    private func makePanel() -> LockOverlayPanel {
        let panel = LockOverlayPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingView(rootView: OverlayRootView(model: model))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    private func show() {
        rebuild()
        for panel in panels.values {
            // `orderFrontRegardless` so the panel is shown even though this app is
            // not the active application (it never becomes active).
            panel.orderFrontRegardless()
            // The window number only exists once the panel is on screen, so the
            // elevation has to happen after ordering it front.
            SkyLight.shared.elevate(panel)
        }
        Log.line("overlay: shown on \(panels.count) display(s)")
        // Polling Spotify only runs while the overlay is up. With the Mac
        // unlocked the app does nothing at all.
        model.start()
        // Keep the display awake so the lyrics stay visible.
        DisplayPower.apply(AppSettings.shared.powerMode)
    }

    private func hide() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        model.stop()
        DisplayPower.release()
        Log.line("overlay: hidden")
    }

    /// Forces the password hint to be visible, for checking the reveal without
    /// moving the mouse.
    func forceHint() {
        model.forceHint()
        Log.line("overlay: hint forced for the snapshot")
    }

    // MARK: - Debug snapshot

    /// Renders the overlay to a PNG.
    ///
    /// The window lives in the lock screen's Space, so it cannot be captured
    /// from the display server. Rendering the view hierarchy directly produces
    /// the same pixels without needing Screen Recording permission.
    func snapshot(to path: String) {
        guard let panel = panels.values.first,
              let view = panel.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            Log.error("snapshot: no window or view")
            return
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            Log.error("snapshot: PNG encode failed")
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            Log.line("snapshot: written to \(path)")
        } catch {
            Log.error("snapshot: \(error.localizedDescription)")
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
