import AppKit

/// What the command line flags do: they apply a look, draw the notch or the
/// previews to pictures, run the notch self test, or show the overlay at once.
/// They exist to check the app without locking the Mac; see `CLAUDE.md` for the list.
extension AppDelegate {

    @MainActor
    func runHarnessFlags() {
        // `--style=music|frenkiieeee|classic|minimal` applies a look, to check it
        // in a snapshot. `--cover-right` puts the cover on the right.
        if let option = CommandLine.arguments.first(where: { $0.hasPrefix("--style=") }),
           let preset = StylePreset(rawValue: String(option.dropFirst(8))) {
            preset.apply(to: AppSettings.shared)
        }
        // `--notch-look=sober|showy|quick|glass|island` does the same for the notch.
        if let option = CommandLine.arguments.first(where: { $0.hasPrefix("--notch-look=") }),
           let look = NotchLook(rawValue: String(option.dropFirst(13))) {
            look.apply(to: AppSettings.shared)
        }
        if CommandLine.arguments.contains("--cover-right") {
            AppSettings.shared.coverOnRight = true
        }

        // `--notch-snapshot <prefix>` draws the notch in every state and quits.
        if let index = CommandLine.arguments.firstIndex(of: "--notch-snapshot"),
           CommandLine.arguments.count > index + 1 {
            let prefix = CommandLine.arguments[index + 1]
            overlayController.sharedModel.setNotchActive(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                let controller = self?.notchController
                let volume = NotchHUD(kind: .volume, value: 0.62)
                controller?.snapshot(to: "\(prefix)-closed.png", .closed)
                controller?.snapshot(to: "\(prefix)-peek.png", .peek)
                controller?.snapshot(to: "\(prefix)-open.png", .open(.home))
                controller?.snapshot(to: "\(prefix)-shelf.png", .open(.shelf))
                controller?.snapshot(to: "\(prefix)-hud-volume.png", .hud(volume))
                controller?.snapshot(to: "\(prefix)-hud-brightness.png",
                                     .hud(NotchHUD(kind: .brightness, value: 0.85)))
                controller?.snapshot(to: "\(prefix)-hud-keyboard.png",
                                     .hud(NotchHUD(kind: .keyboard, value: 0.7)))
                controller?.snapshot(to: "\(prefix)-hud-keyboard-off.png",
                                     .hud(NotchHUD(kind: .keyboard, value: 0)))
                controller?.snapshot(to: "\(prefix)-open-volume.png", .openWithHUD(volume))
                for widget in AppSettings.NotchWidget.allCases {
                    controller?.snapshot(to: "\(prefix)-widget-\(widget.rawValue).png", .widget(widget))
                }
                controller?.snapshot(to: "\(prefix)-notification.png", .notification(open: false))
                controller?.snapshot(to: "\(prefix)-notification-open.png", .notification(open: true))
                controller?.snapshot(to: "\(prefix)-timer-closed.png", .timerClosed)
                NSApp.terminate(nil)
            }
        }

        // `--settings-snapshot <prefix>` draws the live previews of the settings.
        if let index = CommandLine.arguments.firstIndex(of: "--settings-snapshot"),
           CommandLine.arguments.count > index + 1 {
            let prefix = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsPreviewSnapshot.run(prefix: prefix) { NSApp.terminate(nil) }
            }
        }

        // `--notch-selftest <prefix>` (with `--demo`) shows the real notch window,
        // walks it through its states and clicks its controls with real mouse
        // events, saving a picture of each step.
        if let index = CommandLine.arguments.firstIndex(of: "--notch-selftest"),
           CommandLine.arguments.count > index + 1 {
            guard CommandLine.arguments.contains("--demo") else {
                print("--notch-selftest needs --demo, so it never touches the real player")
                exit(2)
            }
            let prefix = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.notchController.runSelfTest(prefix: prefix) { exit(0) }
            }
        }

        // `--present` opens the screensaver at once, for checking it.
        if CommandLine.arguments.contains("--present") {
            overlayController.showPresentation()
        }

        // `--preview` shows the overlay immediately, without waiting for the
        // screen to be locked. Used to iterate on the layout without locking the
        // Mac every time.
        if CommandLine.arguments.contains("--preview") {
            Log.line("=== preview mode requested ===")
            overlayController.showPreview()
            previewVisible = true
            installPreviewEscapeKey()
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

        // `--snapshot-seq <prefix> [count] [interval]` writes several PNGs a
        // moment apart, so the movement of the lyrics can be checked frame by
        // frame.
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-seq"),
           CommandLine.arguments.count > index + 1 {
            let prefix = CommandLine.arguments[index + 1]
            let count = CommandLine.arguments.count > index + 2
                ? (Int(CommandLine.arguments[index + 2]) ?? 26)
                : 26
            let interval = CommandLine.arguments.count > index + 3
                ? (Double(CommandLine.arguments[index + 3]) ?? 1.5)
                : 1.5
            for step in 0..<count {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Double(step) * interval + 2
                ) { [weak self] in
                    self?.overlayController.snapshot(to: "\(prefix)-\(step).png")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(count) * interval + 3) {
                NSApp.terminate(nil)
            }
        }
    }
}
