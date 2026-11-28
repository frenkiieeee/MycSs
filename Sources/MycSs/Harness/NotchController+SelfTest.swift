import AppKit
import SwiftUI

// The notch's own test and capture code: it opens the real window, drives it with
// real mouse events and saves frames. Kept apart from the production code; it
// only runs from the command line (`--notch-selftest`, `--notch-snapshot`).
extension NotchController {

    // MARK: - Captures

    /// What a capture shows.
    enum Shot {
        case closed, peek, open(NotchTab), hud(NotchHUD), openWithHUD(NotchHUD)
        /// Open on the home page with this widget.
        case widget(AppSettings.NotchWidget)
        /// A notification, closed or open.
        case notification(open: Bool)
        /// The closed notch with the timer running.
        case timerClosed
    }

    /// Renders the notch to a PNG in the given state, for checking its look.
    func snapshot(to path: String, _ shot: Shot) {
        let g = DemoFlags.noNotch ? NotchGeometry.plain() : NotchGeometry(notch: CGSize(width: 185, height: 32))
        let demo = NotchModel()
        switch shot {
        case .closed: break
        case .peek: demo.peek(for: 999)
        case .open(let tab): demo.open(tab: tab)
        case .hud(let hud): demo.showHUD(hud, for: 999)
        case .openWithHUD(let hud):
            demo.open(tab: .home)
            demo.showHUD(hud, for: 999)
        case .widget(let widget):
            demo.open(tab: .home)
            demo.widget = widget
        case .notification(let open):
            if open { demo.open(tab: .home) }
            demo.showNotification(NotchNotification(
                id: 1, bundleID: "com.apple.MobileSMS", title: "Marta",
                subtitle: "", body: "¿Comemos hoy? Te espero en la plaza", date: Date()
            ), for: 999)
        case .timerClosed:
            break
        }
        demo.isListening = true
        if case .timerClosed = shot { services.timer.start(minutes: 5) }
        defer { if case .timerClosed = shot { services.timer.reset() } }
        // A timer for the timer widget, so its running look can be judged.
        // (The ruler is the picker, not a running timer: it is drawn as it is.)
        let runs = AppSettings.shared.notchTimerStyle != .ruler
        if case .widget(.timer) = shot, runs { services.timer.start(minutes: 25) }
        defer { if case .widget(.timer) = shot, runs { services.timer.reset() } }
        agenda.prepare()
        NotchSnapshot.isActive = true
        defer { NotchSnapshot.isActive = false }
        // A few files, so the shelf can be judged.
        if case .open(.shelf) = shot, shelf.items.isEmpty {
            shelf.add(["/etc/hosts", "/System/Applications/Notes.app", "/System/Applications/Calendar.app"]
                .map { URL(fileURLWithPath: $0) })
        }
        let size = CGSize(width: g.panelSize.width + 40, height: g.panelSize.height + 16)
        let renderer = ImageRenderer(content: ZStack(alignment: .top) {
            // A stand-in for the desktop under the menu bar.
            LinearGradient(colors: [Color(white: 0.36), Color(white: 0.22)], startPoint: .top, endPoint: .bottom)
            NotchView(notch: demo, model: model, services: services, geometry: g)
                .frame(width: g.panelSize.width, height: g.panelSize.height)
        }.frame(width: size.width, height: size.height))
        renderer.scale = 2
        // A widget the user has not turned on is drawn too: its setting is changed only
        // for this one synchronous render (see `SettingsOverride`).
        if case .widget(let widget) = shot, !AppSettings.shared.isNotchWidgetOn(widget) {
            let list = (AppSettings.shared.notchWidgets + [widget]).map(\.rawValue).joined(separator: ",")
            SettingsOverride.values = [SettingKey.notchWidgets: list]
        }
        let rendered = renderer.nsImage
        SettingsOverride.values = nil
        guard let image = rendered,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Self test

    /// Runs the real notch window through its states and **clicks its controls**,
    /// with real mouse events sent to the window, to prove the buttons work.
    ///
    /// It needs `--demo`, so the commands go to a pretend player and never pause
    /// what the user is listening to.
    func runSelfTest(prefix: String, completion: @escaping () -> Void) {
        isSelfTesting = true
        NotchProbe.isOn = true
        // One line at a time, so a crash or a kill still leaves what was done.
        setvbuf(stdout, nil, _IOLBF, 0)
        var failures = 0

        func pause(_ seconds: Double) async {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        func check(_ name: String, _ passed: Bool) {
            if !passed { failures += 1 }
            print("  \(passed ? "OK  " : "FAIL") \(name)")
        }

        Task { @MainActor in
            print("== Notch self test ==")
            enable()
            await pause(1.6)
            guard let panel else {
                print("  FAIL the notch window was not created")
                completion()
                return
            }
            print("  window \(Int(panel.frame.width))x\(Int(panel.frame.height)), ignores mouse: \(panel.ignoresMouseEvents)")
            print("  window state: \(SkyLight.shared.describe(panel)); frame \(panel.frame); screen \(String(describing: panel.screen?.frame))")
            notch.isListening = true
            await pause(0.5)
            capture(panel, to: "\(prefix)-0-closed.png")
            check("the window is in a Space of its own (it stays while the desktops slide)", isPinned)
            let withMusic = NotchLayout(notch: notch, geometry: geometry, hasTrack: true)
            check("with music, the closed notch grows its sides",
                  withMusic.kind == .wings && withMusic.body.width >= geometry.restSize.width
                    && withMusic.body.width > geometry.contentGap)

            // Nothing playing: it folds back into the hardware notch.
            notch.isListening = false
            await pause(0.6)
            let folded = NotchLayout(notch: notch, geometry: geometry, hasTrack: true)
            check("nothing playing: the notch folds into the hardware one", folded.body == geometry.restSize && folded.ear == 0)
            capture(panel, to: "\(prefix)-0b-idle.png")
            notch.isListening = true
            await pause(0.6)

            // Opening, frame by frame.
            notch.open()
            for frame in 0..<7 {
                await pause(0.035)
                capture(panel, to: "\(prefix)-1-opening-\(frame).png")
            }
            await pause(0.7)
            capture(panel, to: "\(prefix)-2-open.png")
            check("opens", notch.isOpen)
            print("  controls found: \(NotchProbe.frames.keys.sorted().joined(separator: ", "))")

            // Play and pause.
            let wasPlaying = model.isPlayingNow
            await click("playPause", in: panel)
            await pause(0.35)
            check("play/pause button", model.isPlayingNow != wasPlaying)
            await click("playPause", in: panel)
            await pause(0.35)
            check("play/pause again", model.isPlayingNow == wasPlaying)

            // Next and previous.
            await click("next", in: panel)
            check("next button", model.lastCommand == .next)
            await click("previous", in: panel)
            check("previous button", model.lastCommand == .previous)

            // Seeking: a click at three quarters of the bar.
            let dayBeforeSeek = agenda.selectedOffset
            await click("seek", in: panel, at: 0.75)
            check("a click on the music does not change the day", agenda.selectedOffset == dayBeforeSeek)
            if case .seek(let seconds)? = model.lastCommand, model.track.durationSec > 0 {
                let fraction = seconds / model.track.durationSec
                check(String(format: "seek bar (asked for 75%%, got %.0f%%)", fraction * 100),
                      abs(fraction - 0.75) < 0.05)
            } else {
                check("seek bar", false)
            }

            // The calendar: another day.
            await clickDay(1, in: panel)
            await pause(0.3)
            check("calendar day", agenda.selectedOffset == 1)
            capture(panel, to: "\(prefix)-3-tomorrow.png")
            await clickDay(0, in: panel)
            await pause(0.3)

            // Two fingers to the sides over the calendar: days go by.
            let before = agenda.selectedOffset
            await scroll("calendar", by: 70, in: panel)
            check("calendar scroll, fingers right (earlier days)", agenda.selectedOffset < before)
            let earlier = agenda.selectedOffset
            await scroll("calendar", by: -110, in: panel)
            check("calendar scroll, fingers left (later days)", agenda.selectedOffset > earlier)
            capture(panel, to: "\(prefix)-3b-scrolled.png")
            agenda.select(0)
            await pause(0.3)

            // Pressing the date opens the window that creates an event or a reminder.
            await click("calendarTitle", in: panel)
            await pause(0.4)
            check("pressing the date opens the quick add window", QuickAddController.shared.isShown)
            let quick = QuickAddController.shared.model
            quick.kind = .event
            quick.title = "Prueba de evento"
            QuickAddController.shared.save()
            check("an event is created for that day",
                  agenda.eventsForSelectedDay.contains { $0.title == "Prueba de evento" } || agenda.events.contains { $0.title == "Prueba de evento" })
            check("the window closes after saving", !QuickAddController.shared.isShown)
            QuickAddController.shared.present(day: Date(), services: services)
            quick.kind = .reminder
            quick.title = "Prueba de recordatorio"
            check("an empty title is refused", { quick.title = ""; return !quick.save(agenda: agenda, reminders: services.reminders) }())
            quick.title = "Prueba de recordatorio"
            QuickAddController.shared.save()
            check("a reminder is created", services.reminders.items.contains { $0.title == "Prueba de recordatorio" })
            QuickAddController.shared.close()

            // The tabs.
            await click("tab.shelf", in: panel)
            await pause(0.5)
            check("shelf tab", notch.tab == .shelf)
            capture(panel, to: "\(prefix)-4-shelf.png")
            await click("tab.home", in: panel)
            await pause(0.5)
            check("home tab", notch.tab == .home)

            // The proportions: 60 % for the music, 40 % for the widget.
            let widgetShare = HomeLayout.widgetWidth / (HomeLayout.musicWidth + HomeLayout.widgetWidth)
            check(String(format: "the widget takes 40%% of the home page (%.0f%%)", widgetShare * 100),
                  abs(widgetShare - 0.4) < 0.01)

            // The widgets on the right, one at a time.
            await click("widget.reminders", in: panel)
            await pause(0.35)
            check("reminders widget", notch.widget == .reminders)
            let remindersBefore = services.reminders.items.count
            await click("reminder.0", in: panel)
            await pause(0.3)
            check("ticking a reminder completes it", services.reminders.items.count == remindersBefore - 1)
            capture(panel, to: "\(prefix)-3c-reminders.png")

            await click("widget.timer", in: panel)
            await pause(0.35)
            check("timer widget", notch.widget == .timer)
            capture(panel, to: "\(prefix)-3d-timer-presets.png")
            // The ruler as the picker (spec 016), the way the island asks for the time.
            let styleBefore = AppSettings.shared.notchTimerStyle
            // (Frames stay recorded after a control goes: clear them to see what is drawn now.)
            NotchProbe.frames["timer.preset.5"] = nil
            AppSettings.shared.notchTimerStyle = .ruler
            await pause(0.6)
            check("the ruler shows when the style asks for it", NotchProbe.frames["timer.ruler"] != nil)
            capture(panel, to: "\(prefix)-3d-timer-ruler.png")
            NotchProbe.frames["timer.ruler"] = nil
            AppSettings.shared.notchTimerStyle = styleBefore
            await pause(0.9)
            check("the four buttons are back", NotchProbe.frames["timer.preset.5"] != nil)
            await click("timer.preset.5", in: panel)
            await pause(0.4)
            check("a preset starts the timer", services.timer.state == .running)
            // Measured on a closed notch: the open one has the same size either way.
            let closedNotch = NotchModel()
            check("a running timer drops a row under the closed notch",
                  NotchLayout(notch: closedNotch, geometry: geometry, hasTrack: false, timerActive: true).body.height
                    > NotchLayout(notch: closedNotch, geometry: geometry, hasTrack: false, timerActive: false).body.height)
            capture(panel, to: "\(prefix)-3e-timer-running.png")
            await click("timer.toggle", in: panel)
            await pause(0.3)
            check("pausing the timer", services.timer.state == .paused)
            await click("timer.reset", in: panel)
            await pause(0.3)
            check("resetting the timer", services.timer.state == .idle)

            await click("widget.system", in: panel)
            await pause(0.9)
            check("system widget", notch.widget == .system)
            check("the battery and the processor are read", services.system.memoryUsedGB > 0)
            capture(panel, to: "\(prefix)-3f-system.png")

            // The clipboard widget is off by default; turned on only for this check.
            let widgetsBefore = AppSettings.shared.notchWidgets
            AppSettings.shared.setNotchWidget(.clipboard, on: true)
            // The widgets on offer are read when the notch opens, so it is opened again.
            notch.close()
            await pause(0.6)
            notch.open()
            await pause(0.7)
            await click("widget.clipboard", in: panel)
            await pause(0.8)
            if NotchProbe.frames["clip.0"] == nil {
                // The click can land while the notch is still opening: once more.
                await click("widget.clipboard", in: panel)
                await pause(0.8)
            }
            check("clipboard widget lists what was copied", NotchProbe.frames["clip.0"] != nil)
            capture(panel, to: "\(prefix)-3g-clipboard.png")
            // A copied picture is previewed big when the pointer is on it.
            let sample = NSImage(size: NSSize(width: 240, height: 140), flipped: false) { rect in
                NSColor.systemTeal.setFill(); rect.fill()
                NSColor.white.withAlphaComponent(0.6).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 70, dy: 30)).fill()
                return true
            }
            if let png = NSBitmapImageRep(data: sample.tiffRepresentation ?? Data())?.representation(using: .png, properties: [:]) {
                let picture = ClipboardModel.Entry(
                    image: png, width: 240, height: 140, thumbnail: ClipboardModel.thumbnail(of: sample))
                services.clipboard.remember(picture)
                await pause(0.4)
                services.clipboard.hover(picture, true)
                await pause(0.5)
                check("a picture under the pointer is previewed big", NotchProbe.frames["clipboard.preview"] != nil)
                capture(panel, to: "\(prefix)-3g-clipboard-preview.png")
                services.clipboard.hover(picture, false)
                services.clipboard.clear()
            }
            // Opening the notch starts over at the first widget (spec 018), and the
            // notifications widget takes one out with its cross, without opening the app.
            AppSettings.shared.setNotchWidget(.notifications, on: true)
            notch.close()
            await pause(0.6)
            notch.open()
            await pause(0.7)
            check("the notch opens on its first widget again", notch.widget == AppSettings.shared.notchWidgets.first)
            await click("widget.notifications", in: panel)
            await pause(0.8)
            let waiting = services.notifications.history.count
            check("the notifications widget lists what is waiting", waiting > 1 && NotchProbe.frames["notification.0"] != nil)
            if let frame = NotchProbe.frames["notification.0"], let view = panel.contentView {
                // The pointer on the row: its cross appears in place of the time.
                let point = NSPoint(x: frame.midX, y: view.bounds.height - frame.midY)
                if let move = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                    panel.sendEvent(move)
                }
                services.notifications.hover(services.notifications.history[0], true)
                await pause(0.5)
                check("the row under the pointer shows its cross", NotchProbe.frames["notification.0.dismiss"] != nil)
                capture(panel, to: "\(prefix)-3g-notifications.png")
                await click("notification.0.dismiss", in: panel)
                await pause(0.4)
                check("the cross takes it out of the list", services.notifications.history.count == waiting - 1)
            }
            AppSettings.shared.notchWidgets = widgetsBefore
            notch.widget = .calendar
            await pause(0.3)

            // A notification, open: in the header, and a click answers it.
            notch.showNotification(NotchNotification(
                id: 1, bundleID: "com.test.none", title: "Marta", subtitle: "", body: "¿Comemos hoy?", date: Date()
            ), for: 30)
            await pause(0.5)
            check("the notification shows in the open notch's header", NotchProbe.frames["notificationPill"] != nil)
            capture(panel, to: "\(prefix)-3h-notification-open.png")
            await click("notificationPill", in: panel)
            await pause(0.3)
            check("a click on it answers and dismisses it", notch.notification == nil)

            // The size is the user's.
            let scaleBefore = AppSettings.shared.notchScale
            AppSettings.shared.notchScale = 0.7
            check("the size can be reduced", abs(NotchGeometry.openSize.width - 640 * 0.7) < 1)
            AppSettings.shared.notchScale = 1.3
            check("the size can be enlarged", abs(NotchGeometry.openSize.width - 640 * 1.3) < 1)
            AppSettings.shared.notchScale = scaleBefore

            // The volume while open, then closed.
            notch.showHUD(NotchHUD(kind: .volume, value: 0.62), for: 2.5)
            await pause(0.5)
            capture(panel, to: "\(prefix)-5-open-volume.png")
            notch.close()
            for frame in 0..<5 {
                await pause(0.04)
                capture(panel, to: "\(prefix)-6-closing-\(frame).png")
            }
            await pause(0.5)
            check("closes", !notch.isOpen)
            capture(panel, to: "\(prefix)-7-volume.png")
            // The indicator has the closed notch until it fades; a notification waits.
            for _ in 0..<30 where notch.hud != nil { await pause(0.1) }
            notch.showNotification(NotchNotification(
                id: 2, bundleID: "com.apple.MobileSMS", title: "Marta", subtitle: "", body: "¿Comemos hoy?", date: Date()
            ), for: 30)
            await pause(0.6)
            check("a notification widens the closed notch",
                  NotchLayout(notch: notch, geometry: geometry, hasTrack: true).kind == .notification)
            capture(panel, to: "\(prefix)-7b-notification.png")
            notch.dismissNotification()
            await pause(0.4)
            notch.showHUD(NotchHUD(kind: .brightness, value: 0.85), for: 2.0)
            await pause(0.5)
            capture(panel, to: "\(prefix)-8-brightness.png")
            await pause(2.0)
            notch.showHUD(NotchHUD(kind: .keyboard, value: 0.6), for: 2.0)
            await pause(0.6)
            check("the keyboard light shows in the notch", notch.hud?.kind == .keyboard)
            capture(panel, to: "\(prefix)-8b-keyboard.png")
            await pause(2.0)
            notch.peek(for: 2)
            await pause(0.6)
            capture(panel, to: "\(prefix)-9-peek.png")

            // The hover, through the same entry point the view uses.
            notch.isPointerInside = { false }
            notch.hover(true)
            await pause(0.4)
            check("hover opens", notch.isOpen)
            notch.hover(false)
            await pause(0.5)
            check("leaving closes", !notch.isOpen)

            print(failures == 0 ? "== all passed ==" : "== \(failures) FAILED ==")
            completion()
        }
    }

    /// Sends a trackpad-style horizontal scroll to the window over a control, in
    /// several small events like two fingers moving.
    private func scroll(_ id: String, by total: Int32, in panel: NSPanel) async {
        guard let frame = NotchProbe.frames[id], let primary = NSScreen.screens.first else {
            print("  (control '\(id)' not found)")
            return
        }
        // Screen coordinates, with the origin at the top left of the main display.
        let cocoa = NSPoint(x: panel.frame.minX + frame.midX, y: panel.frame.maxY - frame.midY)
        let location = CGPoint(x: cocoa.x, y: primary.frame.height - cocoa.y)

        // The catcher only answers hit tests during a scroll event, so the test
        // says it is one.
        ScrollCatcher.isTesting = true
        defer { ScrollCatcher.isTesting = false }

        // The view the window itself says is under the pointer there.
        guard let view = panel.contentView,
              let catcher = view.hitTest(NSPoint(x: frame.midX, y: view.bounds.height - frame.midY))
                as? ScrollCatcher.CatcherView
        else {
            print("  (the calendar does not take scrolls)")
            return
        }
        let steps: Int32 = 6
        for _ in 0..<steps {
            guard let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: 0, wheel2: total / steps, wheel3: 0
            ) else { continue }
            cg.location = location
            // A synthetic event has no window, so its location is in screen
            // coordinates and the window would route it wrongly; it is handed to
            // the view the window picked.
            if let event = NSEvent(cgEvent: cg) { catcher.scrollWheel(with: event) }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    /// Clicks the day `offset` of the week strip, wherever it is now drawn.
    private func clickDay(_ offset: Int, in panel: NSPanel) async {
        // The selected day is the fourth of seven, so the others are around it.
        let slot = offset - agenda.selectedOffset + AgendaModel.visibleSide
        guard (0..<7).contains(slot) else {
            agenda.select(offset)
            return
        }
        await click("strip", in: panel, at: (CGFloat(slot) + 0.5) / 7)
    }

    /// Sends a real mouse click to the window, on a control the view reported.
    private func click(_ id: String, in panel: NSPanel, at fraction: CGFloat = 0.5) async {
        guard let frame = NotchProbe.frames[id], let view = panel.contentView else {
            print("  (control '\(id)' not found)")
            return
        }
        // From SwiftUI's coordinates (top left) to the window's (bottom left).
        let location = NSPoint(
            x: frame.minX + frame.width * fraction,
            y: view.bounds.height - frame.midY
        )
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { continue }
            panel.sendEvent(event)
            try? await Task.sleep(nanoseconds: 70_000_000)
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    /// Captures the window as the window server composes it (so the shape, the
    /// transparency and the frames in the middle of an animation are the real
    /// ones), over a grey background.
    ///
    /// The function is looked up at run time: the SDK no longer declares it, but
    /// it is still there, and a window of the app itself needs no permission.
    private func capture(_ panel: NSPanel, to path: String) {
        typealias CaptureFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let function = unsafeBitCast(symbol, to: CaptureFunction.self)
        // Only this window (1 << 3), ignoring its shadow frame (1 << 0), at full
        // resolution (1 << 3).
        guard let shot = function(.null, 1 << 3, UInt32(panel.windowNumber), (1 << 0) | (1 << 3))?
            .takeRetainedValue()
        else { return }

        let size = panel.frame.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(white: 0.42, alpha: 1), NSColor(white: 0.26, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -90)
        NSImage(cgImage: shot, size: size).draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
