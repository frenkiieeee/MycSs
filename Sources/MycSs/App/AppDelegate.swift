import AppKit

/// The application delegate.
///
/// The entry point lives in `main.swift`, which wires this object up and starts
/// the run loop.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// `NSApplication.delegate` is weak, so the delegate has to be retained here.
    static var retainedDelegate: AppDelegate?

    private let lockState = LockState()
    var overlayController: LockOverlayController!
    var notchController: NotchController!
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    var previewVisible = false
    /// The monitor that watches for the Escape key while the preview is up.
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.line("=== MycSs starting (pid \(ProcessInfo.processInfo.processIdentifier)) ===")

        installStatusItem()
        installMenu()
        updateStatusItemVisibility()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusItemVisibility() }
        }

        overlayController = LockOverlayController(lockState: lockState)
        overlayController.start()
        notchController = NotchController(model: overlayController.sharedModel)
        AccessibilityStatus.shared.start()

        lockState.start()

        // The global shortcut for the screensaver.
        HotKeyManager.shared.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.overlayController.togglePresentation() }
        }
        HotKeyManager.shared.reload()
        NotificationCenter.default.addObserver(
            forName: HotKeyManager.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installMenu() }
        }

        // The Spotify polling runs for the whole life of the app: while the Mac
        // is unlocked the app keeps knowing which track is playing, so the
        // lyrics are already loading when the screen is locked.
        overlayController.startListening()

        // Safety net: the lock/unlock notifications are the primary signal, but a
        // periodic tick guarantees the overlay appears even if a notification is
        // missed (for example if the app was launched while the screen was
        // already locked).
        // The overlay has to follow the lock screen into its Space, and the lock
        // screen creates that Space a fraction of a second after the lock. A
        // short tick keeps that follow-up tight, so the lyrics appear as soon
        // as the lock screen is really on screen.
        tickTimer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.overlayController.tick()
                // The lock screen creates its Space a moment after the lock
                // notification, so the overlay follows it into place.
                self?.overlayController.followLockScreen()
                if let self {
                    self.notchController.update(
                        locked: self.overlayController.isScreenLocked,
                        overlayVisible: self.overlayController.isOverlayVisible
                    )
                }
            }
        }
        tickTimer?.tolerance = 0.2
        RunLoop.main.add(tickTimer!, forMode: .common)

        // Command line flags for checking the app without the real screen (see Harness/).
        runHarnessFlags()

        Log.line("=== MycSs running ===")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.line("=== MycSs terminating ===")
        SkyLight.shared.teardown()
    }

    // MARK: - Menu bar

    /// Hides the menu bar icon when the user asked and the notch is on: the notch
    /// is then the way into the preferences. With the notch off the icon always
    /// shows, so there is never an app without a way in.
    ///
    /// **It remembers what it last did instead of asking the status item.** Setting
    /// `isVisible` makes AppKit write to `UserDefaults`, which posts the very
    /// notification this runs on, *inside* the setter and before `isVisible` has
    /// changed. Comparing with `statusItem.isVisible` therefore called the setter
    /// again, forever, until the stack overflowed and the app closed.
    private func updateStatusItemVisibility() {
        let settings = AppSettings.shared
        let visible = !(settings.hideMenuBarIcon && settings.notchEnabled)
        guard visible != lastStatusItemVisible else { return }
        lastStatusItemVisible = visible
        statusItem.isVisible = visible
        Log.line("menu bar icon: \(visible ? "shown" : "hidden")")
    }

    /// What `updateStatusItemVisibility` last set. `nil` until it runs once.
    private var lastStatusItemVisible: Bool?

    /// Opening MycSs again (Finder, Spotlight) opens the preferences: with the icon
    /// hidden it is the other way in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The mascot, packaged by build-app.sh. A plain `swift build` run has no
        // bundle resources, so it falls back to the SF Symbol.
        if let url = Bundle.main.url(forResource: "MenuIcon", withExtension: "png"),
           let mascot = NSImage(contentsOf: url) {
            mascot.size = NSSize(width: 18, height: 18)
            // A template image: the system tints it for light and dark menu
            // bars and for the highlighted state, like its own icons.
            mascot.isTemplate = true
            mascot.accessibilityDescription = "MycSs"
            statusItem.button?.image = mascot
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "MycSs"
            )
        }
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

        // The lyrics as a screensaver. The shortcut is shown next to it.
        let lyrics = NSMenuItem(
            title: "Letras",
            action: #selector(togglePresentation),
            keyEquivalent: AppSettings.shared.hotKeyEnabled ? AppSettings.shared.hotKeyCharacter : ""
        )
        lyrics.keyEquivalentModifierMask = HotKeyManager.appKitModifiers(AppSettings.shared.hotKeyModifiers)
        lyrics.target = self
        menu.addItem(lyrics)

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

    @objc @MainActor private func togglePresentation() {
        overlayController.togglePresentation()
    }

    @objc @MainActor private func togglePreview() {
        if previewVisible {
            overlayController.hidePreview()
        } else {
            overlayController.showPreview()
        }
        previewVisible.toggle()
    }

    /// Closes the preview when Escape is pressed.
    ///
    /// The preview covers the whole screen, so the menu bar item that would
    /// normally turn it off is hard to reach. Escape is the escape hatch.
    ///
    /// The event is only acted on when it comes from a real key press: the app
    /// also receives synthetic key events from other sources, and reacting to
    /// those would close the preview on its own.
    func installPreviewEscapeKey() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,  // Escape
                  self?.previewVisible == true,
                  event.isARepeat == false,
                  event.window != nil
            else { return event }
            MainActor.assumeIsolated {
                self?.overlayController.hidePreview()
                self?.previewVisible = false
            }
            return nil
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
