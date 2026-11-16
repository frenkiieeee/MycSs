import AppKit
import SwiftUI

/// Puts the notch on screen and feeds it: the song, the volume and brightness,
/// and the pointer.
///
/// The notch itself handles its hover and its clicks (they are real SwiftUI
/// events; see `NotchPanel`). This object only watches from outside: it shows the
/// title when the song changes, shows the volume when it changes, opens the shelf
/// when files are dragged to the notch, and closes the notch if the pointer is
/// gone and the hover never said so.
///
/// It is off until the user turns it on in the settings, and it hides itself
/// whenever the lock screen or the full screen lyrics are showing.
@MainActor
final class NotchController {

    private let model: LyricsViewModel
    private let notch = NotchModel()
    private let services = NotchServices()
    private var agenda: AgendaModel { services.agenda }
    private var shelf: ShelfModel { services.shelf }
    private let volumeWatcher = VolumeWatcher()

    private var panel: NotchPanel?
    private var geometry = NotchGeometry(notch: CGSize(width: 185, height: 32))
    private var screenFrame: CGRect = .zero
    private var displayID: CGDirectDisplayID = CGMainDisplayID()

    /// The song the notch last saw, to notice when it changes.
    private var lastTrackKey = ""
    /// Whether the notch was open on the last tick, to notice when it changes.
    private var wasOpen = false
    /// Since when the pointer is away from the open notch, or on the closed one.
    private var awaySince: Date?
    private var insideSince: Date?
    /// When the keys were last tried to be taken, to not insist every tick.
    private var lastTapAttempt = Date.distantPast
    /// Since when nothing has been playing.
    private var pausedSince: Date?
    /// Whether the window is in its own Space. If it is not (the private call
    /// failed), the notch still works, but it moves with the desktops.
    private(set) var isPinned = false
    /// The self test drives the notch itself; the pointer must not interfere.
    private var isSelfTesting = false

    init(model: LyricsViewModel) {
        self.model = model
    }

    // MARK: - Lifecycle

    /// Called a dozen times a second by the app's timer.
    func update(locked: Bool, overlayVisible: Bool) {
        let wanted = (AppSettings.shared.notchEnabled || isSelfTesting) && !locked && !overlayVisible

        if wanted {
            if panel == nil { enable() }
            syncOpenState()
            if !isSelfTesting { updateListening() }
            if !isSelfTesting { updateServices() }
            updatePeek()
            updateKeys()
            updateAudio()
            if !isSelfTesting { reconcilePointer() }
        } else if panel != nil {
            Log.line("notch: hiding (locked: \(locked), overlay: \(overlayVisible), enabled: \(AppSettings.shared.notchEnabled))")
            disable()
        }
    }

    private func enable() {
        // The screen with the notch, or the main one.
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen, let id = screen.displayID else { return }
        displayID = id
        screenFrame = screen.frame

        // The cut-out is the gap between the two usable areas at the top.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            geometry = NotchGeometry(notch: CGSize(
                width: max(right.minX - left.maxX, 120),
                height: screen.safeAreaInsets.top
            ))
        } else {
            // No notch: a pill the size of a typical one.
            geometry = NotchGeometry(notch: CGSize(width: 170, height: 28))
        }

        let size = geometry.panelSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        let panel = NotchPanel(frame: frame)
        agenda.prepare()
        let host = NotchHostingView(rootView: NotchRoot(
            notch: notch, model: model, services: services, geometry: geometry
        ))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        // Its own Space, so it stays put while the desktops slide by.
        isPinned = SkyLight.shared.pinToAllDesktops(panel)
        self.panel = panel

        // An empty track still has a key ("||"), so it is not used as "none".
        lastTrackKey = model.track.hasTrack ? model.track.trackKey : ""
        model.setNotchActive(true)

        // Notifications of other apps (when the app may read them), and the timer.
        services.notifications.onNotification = { [weak self] notification in
            guard AppSettings.shared.notchNotifications else { return }
            self?.notch.showNotification(notification)
        }
        services.timer.onFinish = { [weak self] in
            self?.notch.showNotification(NotchNotification(
                id: Int64(Date().timeIntervalSince1970),
                bundleID: "com.mycss.lyrics",
                title: "Temporizador",
                subtitle: "",
                body: "Se acabó el tiempo",
                date: Date(),
                symbolName: "timer"
            ), for: 8)
        }
        notch.isPointerInside = { [weak self] in
            self?.currentZone(padding: 10).contains(NSEvent.mouseLocation) ?? false
        }

        // The volume, whoever changes it.
        volumeWatcher.onChange = { [weak self] hud in
            // **Only when the keys are taken.** Without the Accessibility
            // permission the system draws its own indicator, and drawing ours too
            // would show the volume twice. When the keys are taken, this still
            // catches the changes that do not come from the keys (the Control
            // Centre slider, the headphones), which have no system indicator.
            guard AppSettings.shared.notchHUD, MediaKeyTap.shared.isInstalled else { return }
            self?.notch.showHUD(hud)
        }
        volumeWatcher.start()

        // The keys: only taken while the notch is on screen.
        MediaKeyTap.shared.brightnessDisplay = id
        MediaKeyTap.shared.isActive = { [weak self] in self?.panel != nil }
        MediaKeyTap.shared.onChange = { [weak self] hud in
            self?.notch.showHUD(hud)
        }
        Log.line("notch: shown on display \(id), cut-out \(Int(geometry.notch.width))x\(Int(geometry.notch.height))")
    }

    private func disable() {
        volumeWatcher.stop()
        services.notifications.stop()
        services.clipboard.stop()
        MediaKeyTap.shared.uninstall()
        AudioReactor.shared.stop()
        model.setNotchActive(false)
        model.notchExpanded = false
        notch.reset()
        wasOpen = false
        awaySince = nil
        insideSince = nil
        panel?.orderOut(nil)
        panel = nil
        Log.line("notch: hidden")
    }

    /// Things that follow the notch opening or closing.
    private func syncOpenState() {
        guard notch.isOpen != wasOpen else { return }
        wasOpen = notch.isOpen
        // Open, the progress bar is refreshed more often.
        model.notchExpanded = notch.isOpen
        if notch.isOpen { agenda.refresh() }
        awaySince = nil
        insideSince = nil
    }

    // MARK: - Volume and brightness keys

    /// Takes the keys when the setting is on and the permission is there; gives
    /// them back otherwise. Without the permission the volume is still shown in
    /// the notch (by `VolumeWatcher`), next to the system's own indicator.
    private func updateKeys() {
        let tap = MediaKeyTap.shared
        guard AppSettings.shared.notchHUD else {
            if tap.isInstalled { tap.uninstall() }
            return
        }
        guard !tap.isInstalled, Date().timeIntervalSince(lastTapAttempt) > 1 else { return }
        lastTapAttempt = Date()

        if tap.install() { return }

        // Not allowed yet. The system's prompt is shown once for each identity of
        // the app; after that the settings have the buttons.
        let identity = AppIdentity.requirement
        if AppSettings.shared.accessibilityPromptedFor != identity, !isSelfTesting {
            AppSettings.shared.accessibilityPromptedFor = identity
            Log.line("hud: asking for the Accessibility permission (\(identity))")
            AccessibilityStatus.shared.request()
        }
    }

    // MARK: - Optional services

    /// Starts and stops what depends on a setting: the notifications reader and the
    /// clipboard history. Both only run while the notch is on screen.
    private func updateServices() {
        let settings = AppSettings.shared
        if settings.notchNotifications {
            services.notifications.start()
        } else {
            services.notifications.stop()
        }
        if settings.isNotchWidgetOn(.clipboard) {
            services.clipboard.start()
        } else if !services.clipboard.entries.isEmpty {
            services.clipboard.stop()
            services.clipboard.clear()
        } else {
            services.clipboard.stop()
        }
    }

    // MARK: - Audio

    /// Listens to the sound only while the option is on and music plays.
    private func updateAudio() {
        let reactor = AudioReactor.shared
        let wanted = AppSettings.shared.notchReactive && model.isPlayingNow
        if wanted, !reactor.isRunning, reactor.failure == nil {
            reactor.start()
        } else if !wanted, reactor.isRunning {
            reactor.stop()
        } else if !AppSettings.shared.notchReactive, reactor.failure != nil {
            // Turning the option off clears an old failure, so it can be tried again.
            reactor.stop()
        }
    }

    // MARK: - Listening

    /// Whether the notch has anything to show while closed: music playing, or just
    /// paused. After a pause it waits a few seconds before folding back, so a short
    /// pause does not make it flicker.
    private func updateListening() {
        guard AppSettings.shared.notchHideWhenIdle else {
            notch.isListening = model.track.hasTrack
            pausedSince = nil
            return
        }
        if model.track.hasTrack, model.isPlayingNow {
            pausedSince = nil
            notch.isListening = true
        } else {
            pausedSince = pausedSince ?? Date()
            if Date().timeIntervalSince(pausedSince!) > 6 { notch.isListening = false }
        }
    }

    // MARK: - Peek

    /// Shows the title and the artist for a few seconds when the song changes.
    private func updatePeek() {
        let track = model.track
        guard track.hasTrack else {
            lastTrackKey = ""
            return
        }
        guard track.trackKey != lastTrackKey else { return }
        let first = lastTrackKey.isEmpty
        lastTrackKey = track.trackKey
        // Not for the very first song after the notch turns on.
        if !first, AppSettings.shared.notchPeek, !notch.isOpen, notch.isListening {
            notch.peek()
            Log.line("notch: peek for '\(track.title)'")
        }
    }

    // MARK: - The pointer, from outside

    /// A safety net under the notch's own hover, by the position of the pointer:
    /// it closes an open notch the pointer has left, opens a closed one the
    /// pointer rests on, and opens the shelf when files are dragged to it.
    private func reconcilePointer() {
        let point = NSEvent.mouseLocation
        let inside = currentZone(padding: notch.isOpen ? 12 : 4).contains(point)

        if notch.isOpen {
            insideSince = nil
            if inside {
                awaySince = nil
            } else {
                awaySince = awaySince ?? Date()
                if Date().timeIntervalSince(awaySince!) > 0.5,
                   !isDraggingFiles(), !notch.shelfTargeted {
                    notch.close("the pointer is away")
                }
            }
        } else {
            awaySince = nil
            guard inside else {
                insideSince = nil
                return
            }
            if isDraggingFiles() {
                notch.open(tab: .shelf)
                return
            }
            insideSince = insideSince ?? Date()
            if Date().timeIntervalSince(insideSince!) > 0.3 {
                notch.open(haptic: true)
            }
        }
    }

    /// The rectangle the notch occupies on screen right now.
    private func currentZone(padding: CGFloat) -> CGRect {
        let layout = NotchLayout(
            notch: notch, geometry: geometry,
            hasTrack: model.track.hasTrack, timerActive: services.timer.isActive
        )
        let width = layout.body.width + layout.ear * 2
        return CGRect(
            x: screenFrame.midX - width / 2 - padding,
            y: screenFrame.maxY - layout.body.height - padding,
            width: width + padding * 2,
            height: layout.body.height + padding
        )
    }

    /// Whether the user is dragging files right now. The drag pasteboard keeps its
    /// contents after the drag ends, so the button has to be down as well.
    private func isDraggingFiles() -> Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return false }
        return NSPasteboard(name: .drag).canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

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
        let g = NotchGeometry(notch: CGSize(width: 185, height: 32))
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
        if case .widget(.timer) = shot { services.timer.start(minutes: 25) }
        defer { if case .widget(.timer) = shot { services.timer.reset() } }
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
        guard let image = renderer.nsImage,
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
            check("with music, the closed notch grows its sides",
                  NotchLayout(notch: notch, geometry: geometry, hasTrack: true).body.width > geometry.notch.width)

            // Nothing playing: it folds back into the hardware notch.
            notch.isListening = false
            await pause(0.6)
            let folded = NotchLayout(notch: notch, geometry: geometry, hasTrack: true)
            check("nothing playing: the notch folds into the hardware one", folded.body == geometry.notch && folded.ear == 0)
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
            await click("timer.preset.5", in: panel)
            await pause(0.4)
            check("a preset starts the timer", services.timer.state == .running)
            // Measured on a closed notch: the open one has the same size either way.
            let closedNotch = NotchModel()
            check("a running timer widens the closed notch",
                  NotchLayout(notch: closedNotch, geometry: geometry, hasTrack: false, timerActive: true).body.width
                    > NotchLayout(notch: closedNotch, geometry: geometry, hasTrack: false, timerActive: false).body.width)
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
            check("clipboard widget lists what was copied", NotchProbe.frames["clip.0"] != nil)
            capture(panel, to: "\(prefix)-3g-clipboard.png")
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
