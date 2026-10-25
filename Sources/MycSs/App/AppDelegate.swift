import AppKit

/// The application delegate.
///
/// The entry point lives in `main.swift`, which wires this object up and starts
/// the run loop.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// `NSApplication.delegate` is weak, so the delegate has to be retained here.
    static var retainedDelegate: AppDelegate?

    private let lockState = LockState()
    private var overlayController: LockOverlayController!
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var previewVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.line("=== MycSs starting (pid \(ProcessInfo.processInfo.processIdentifier)) ===")

        installStatusItem()
        installMenu()

        overlayController = LockOverlayController(lockState: lockState)
        overlayController.start()

        lockState.start()

        // Safety net: the lock/unlock notifications are the primary signal, but a
        // periodic tick guarantees the overlay appears even if a notification is
        // missed (for example if the app was launched while the screen was
        // already locked).
        tickTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlayController.tick() }
        }
        tickTimer?.tolerance = 0.2
        RunLoop.main.add(tickTimer!, forMode: .common)

        // `--preview` shows the overlay immediately, without waiting for the
        // screen to be locked. Used to iterate on the layout without locking the
        // Mac every time.
        if CommandLine.arguments.contains("--preview") {
            Log.line("=== preview mode requested ===")
            overlayController.showPreview()
        }

        // `--snapshot <path>` writes a PNG of the overlay, for checking the
        // rendering without a screen recording permission.
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            // Give the lyrics a moment to load before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                // `--snapshot-hint` forces the password hint to be visible, so
                // the reveal can be checked without moving the mouse.
                if CommandLine.arguments.contains("--snapshot-hint") {
                    self?.overlayController.forceHint()
                }
                self?.overlayController.snapshot(to: path)
                NSApp.terminate(nil)
            }
        }

        Log.line("=== MycSs running ===")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.line("=== MycSs terminating ===")
        SkyLight.shared.teardown()
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "MycSs"
        )
    }

    private func installMenu() {
        let menu = NSMenu()

        let state = NSMenuItem(
            title: lockState.isLocked ? "Bloqueada" : "Desbloqueada",
            action: nil,
            keyEquivalent: ""
        )
        state.isEnabled = false
        menu.addItem(state)

        menu.addItem(.separator())

        // Whether the overlay shows at all.
        let enabled = NSMenuItem(
            title: "Overlay en pantalla de bloqueo",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabled.target = self
        enabled.state = AppSettings.shared.overlayEnabled ? .on : .off
        menu.addItem(enabled)

        // Display behaviour.
        let displayItem = NSMenuItem(title: "Pantalla", action: nil, keyEquivalent: "")
        let displayMenu = NSMenu()
        for mode in AppSettings.DisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(setDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = AppSettings.shared.displayMode == mode ? .on : .off
            displayMenu.addItem(item)
        }
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)

        // Development aid: show the overlay without locking the screen.
        let preview = NSMenuItem(
            title: "Vista previa (sin bloquear)",
            action: #selector(togglePreview),
            keyEquivalent: "p"
        )
        preview.target = self
        menu.addItem(preview)

        menu.addItem(.separator())

        let preferences = NSMenuItem(
            title: "Preferencias…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferences.target = self
        menu.addItem(preferences)

        let quit = NSMenuItem(title: "Salir", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleEnabled() {
        let settings = AppSettings.shared
        settings.overlayEnabled = !settings.overlayEnabled
        Log.line("menu: overlay enabled = \(settings.overlayEnabled)")
        // Rebuild the menu so the checkmark reflects the new state.
        installMenu()
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppSettings.DisplayMode(rawValue: raw)
        else { return }
        AppSettings.shared.displayMode = mode
        Log.line("menu: display mode = \(mode.rawValue)")
        installMenu()
        // Apply immediately if the overlay is currently up.
        if lockState.isLocked {
            DisplayPower.apply(AppSettings.shared.powerMode)
        }
    }

    @objc @MainActor private func togglePreview() {
        if previewVisible {
            overlayController.hidePreview()
        } else {
            overlayController.showPreview()
        }
        previewVisible.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
