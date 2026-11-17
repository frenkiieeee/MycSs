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

    // Internal, not private: the harness (Harness/NotchController+SelfTest.swift) drives them.
    let model: LyricsViewModel
    let notch = NotchModel()
    let services = NotchServices()
    var agenda: AgendaModel { services.agenda }
    var shelf: ShelfModel { services.shelf }
    private let volumeWatcher = VolumeWatcher()

    var panel: NotchPanel?
    /// The notch on the other screens, when the user wants it there too.
    private struct ExtraNotch {
        let id: CGDirectDisplayID
        let panel: NotchPanel
        let screenFrame: CGRect
        let geometry: NotchGeometry
    }
    private var extras: [ExtraNotch] = []
    var geometry = NotchGeometry(notch: CGSize(width: 185, height: 32))
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
    var isSelfTesting = false

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
            if !isSelfTesting { syncExtraNotches() }
            updatePeek()
            updateKeys()
            updateAudio()
            if !isSelfTesting { reconcilePointer() }
        } else if panel != nil {
            Log.line("notch: hiding (locked: \(locked), overlay: \(overlayVisible), enabled: \(AppSettings.shared.notchEnabled))")
            disable()
        }
    }

    func enable() {
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
            notch: notch, model: model, services: services, geometry: geometry, display: id
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
            guard let self else { return false }
            let openOn = self.notch.openDisplay == 0 ? self.displayID : self.notch.openDisplay
            return self.currentZone(padding: 10, display: openOn).contains(NSEvent.mouseLocation)
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
        removeExtraNotches()
        Log.line("notch: hidden")
    }

    // MARK: - Other screens

    /// The size of the cut-out of a screen, or a pill where there is none.
    private func notchGeometry(for screen: NSScreen) -> NotchGeometry {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            return NotchGeometry(notch: CGSize(
                width: max(right.minX - left.maxX, 120),
                height: screen.safeAreaInsets.top
            ))
        }
        return NotchGeometry(notch: CGSize(width: 170, height: 28))
    }

    /// Keeps one notch on every other screen while the setting asks for it, and
    /// follows screens being plugged in, unplugged or moved.
    private func syncExtraNotches() {
        let wanted: [NSScreen] = AppSettings.shared.notchDisplays == .all
            ? NSScreen.screens.filter { $0.displayID != displayID && $0.displayID != nil }
            : []
        let same = wanted.count == extras.count
            && zip(wanted, extras).allSatisfy { $0.displayID == $1.id && $0.frame == $1.screenFrame }
        guard !same else { return }

        removeExtraNotches()
        for screen in wanted {
            guard let id = screen.displayID else { continue }
            let geometry = notchGeometry(for: screen)
            let size = geometry.panelSize
            let frame = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width, height: size.height
            )
            let panel = NotchPanel(frame: frame)
            let host = NotchHostingView(rootView: NotchRoot(
                notch: notch, model: model, services: services, geometry: geometry, display: id
            ))
            host.frame = NSRect(origin: .zero, size: size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.orderFrontRegardless()
            _ = SkyLight.shared.pinToAllDesktops(panel)
            extras.append(ExtraNotch(id: id, panel: panel, screenFrame: screen.frame, geometry: geometry))
            Log.line("notch: also on display \(id), cut-out \(Int(geometry.notch.width))x\(Int(geometry.notch.height))")
        }
    }

    private func removeExtraNotches() {
        guard !extras.isEmpty else { return }
        for extra in extras { extra.panel.orderOut(nil) }
        extras = []
        Log.line("notch: removed from the other displays")
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
        // Open, the notch that matters is the one that is open; closed, the one under the pointer.
        let openOn = notch.openDisplay == 0 ? displayID : notch.openDisplay
        let under = notch.isOpen ? nil : displayUnderPointer(padding: 4)
        let inside = notch.isOpen
            ? currentZone(padding: 12, display: openOn).contains(NSEvent.mouseLocation)
            : under != nil
        if let under { notch.hoverDisplay = under }

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

    /// The rectangle the notch occupies on a screen right now (0 is the main one).
    private func currentZone(padding: CGFloat, display: CGDirectDisplayID = 0) -> CGRect {
        var frame = screenFrame
        var geo = geometry
        var id = displayID
        if display != 0, display != displayID, let extra = extras.first(where: { $0.id == display }) {
            frame = extra.screenFrame
            geo = extra.geometry
            id = extra.id
        }
        let layout = NotchLayout(
            notch: notch, geometry: geo,
            hasTrack: model.track.hasTrack, timerActive: services.timer.isActive,
            display: id
        )
        let width = layout.body.width + layout.ear * 2
        return CGRect(
            x: frame.midX - width / 2 - padding,
            y: frame.maxY - layout.body.height - padding,
            width: width + padding * 2,
            height: layout.body.height + padding
        )
    }

    /// The screen whose notch the pointer is on, if any.
    private func displayUnderPointer(padding: CGFloat) -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        let ids = [displayID] + extras.map(\.id)
        return ids.first { currentZone(padding: padding, display: $0).contains(point) }
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
}
