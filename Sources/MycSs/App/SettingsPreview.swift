import AppKit
import Observation
import SwiftUI

/// Live previews for the settings window: what is being configured is drawn
/// right above the controls, with a demo song, and follows every change.
///
/// Nothing here touches the real player: the models run in demo mode, on their own
/// clock.

// MARK: - Change counter

/// Goes up every time a setting changes. A page that reads it is drawn again, so
/// a preview never lags behind a control. (`AppSettings` keeps its values in
/// `UserDefaults`, which SwiftUI cannot watch by itself.)
@MainActor
@Observable
final class SettingsRevision {
    static let shared = SettingsRevision()
    private(set) var value = 0

    /// What the app's own settings were at the last change, to tell a real change
    /// from AppKit writing its own keys.
    private var last: [String: Any] = [:]
    /// Keys that change while the app is used and do not alter how anything looks.
    private let ignored: Set<String> = ["notchWidgetSelected", "accessibilityPromptedFor"]

    private init() {
        last = current()
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func current() -> [String: Any] {
        UserDefaults.standard.dictionaryRepresentation().filter {
            !ignored.contains($0.key) && !$0.key.hasPrefix("NS") && !$0.key.hasPrefix("Apple")
                && !$0.key.hasPrefix("METAL") && !$0.key.hasPrefix("com.apple")
        }
    }

    private func check() {
        let now = current()
        if !NSDictionary(dictionary: now).isEqual(to: last) {
            last = now
            value += 1
        }
    }
}

// MARK: - Seeing a style without applying it

/// Draws a style on the preview **without applying it**. It puts the style's values
/// in a temporary layer (`SettingsOverride`), has the view drawn once to a picture,
/// and takes the layer off, a few times a second, so the picture keeps moving a little.
@MainActor
@Observable
final class StylePreviewer {
    static let shared = StylePreviewer()

    private(set) var id: String?
    private(set) var domain: StyleDomain?
    private(set) var title = ""
    private(set) var image: NSImage?

    @ObservationIgnored private var values: [String: Any?] = [:]
    @ObservationIgnored private var timer: Timer?

    /// Pointing at a style shows it; pointing at the same one again goes back.
    func toggle(_ item: StyleItem, _ domain: StyleDomain) {
        if id == item.id { stop(); return }
        id = item.id
        self.domain = domain
        title = item.title
        values = StyleLibrary.shared.previewValues(item.id, domain)
        render()
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        id = nil
        domain = nil
        image = nil
    }

    func isShowing(_ id: String) -> Bool { self.id == id }

    private func render() {
        guard let domain else { return }
        SettingsOverride.values = values
        defer { SettingsOverride.values = nil }

        switch domain {
        case .lyrics:
            let screen = CGSize(width: 1440, height: 900)
            let renderer = ImageRenderer(content: OverlayRootView(model: OverlayPreview.model, revision: 0)
                .environment(\.isSettingsPreview, true)
                .frame(width: screen.width, height: screen.height)
                .background(Color.black))
            renderer.scale = 0.6
            image = renderer.nsImage
        case .notch:
            let size = CGSize(width: 640, height: NotchStage.room.height * 0.86)
            NotchSnapshot.isActive = true
            defer { NotchSnapshot.isActive = false }
            let renderer = ImageRenderer(content: NotchStage(state: NotchPreviewState.shared, size: size))
            renderer.scale = 2
            image = renderer.nsImage
        }
    }
}

/// The note on top of the preview while a style is being seen: its name, whether
/// it is applied, and the two ways out.
struct StyleViewingBanner: View {
    let domain: StyleDomain
    @Bindable var previewer = StylePreviewer.shared

    var body: some View {
        if previewer.domain == domain, let id = previewer.id {
            HStack(spacing: 10) {
                Image(systemName: "eye")
                Text("Viendo «\(previewer.title)» sin aplicar")
                    .font(.callout.weight(.medium))
                Button("Aplicar") {
                    StyleLibrary.shared.apply(id, domain)
                    previewer.stop()
                }
                Button("Volver a lo mío") { previewer.stop() }
            }
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(brandYellow.opacity(0.18)))
            .overlay(Capsule().strokeBorder(brandYellow.opacity(0.5)))
            .transition(.opacity)
        }
    }
}

// MARK: - The lock screen and the lyrics

/// The overlay at a small size: the clock, the cover, the player and the lyrics,
/// with the styles, the fonts and the background that are chosen.
struct OverlayPreview: View {

    /// One model for every preview: a demo song that loops.
    @MainActor
    static let model = LyricsViewModel(demo: true)

    @Bindable var revision = SettingsRevision.shared
    /// Whether this preview plays the clock going away and coming back.
    var clockCycle = false
    /// The screen the overlay is drawn for. The layout is worked out at this size
    /// and shrunk to fit.
    private let screen = CGSize(width: 1440, height: 900)

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / screen.width
            OverlayRootView(model: Self.model, revision: revision.value)
                .environment(\.isSettingsPreview, true)
                .frame(width: screen.width, height: screen.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(screen.width / screen.height, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
        // A change in a control eases in instead of jumping.
        .animation(.smooth(duration: 0.35), value: revision.value)
        .allowsHitTesting(false)
        .onAppear { Self.attach(clockCycle: clockCycle) }
        .onDisappear { Self.detach() }
    }

    /// How many previews are on screen. Moving from one settings page to another
    /// shows the next one before the old one is gone, so the model only stops when
    /// the last of them leaves.
    @MainActor private static var users = 0

    @MainActor private static func attach(clockCycle: Bool) {
        users += 1
        model.previewClockCycle = clockCycle
        model.startPreview()
        // The picture renderer shows a view only to draw it once: no entrance.
        if !SettingsPreviewSnapshot.isRunning { model.replayEntrance() }
    }

    @MainActor private static func detach() {
        users = max(0, users - 1)
        // The picture renderer shows and drops a view every time; it keeps going.
        if users == 0, !SettingsPreviewSnapshot.isRunning { model.stopPreview() }
    }
}

/// The preview, with the states to try and a button to see the entrance again.
struct OverlayPreviewCard: View {
    var showsEntranceButton = false
    var clockCycle = false

    @Bindable var model = OverlayPreview.model
    @Bindable var previewer = StylePreviewer.shared

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                OverlayPreview(clockCycle: clockCycle)
                if previewer.domain == .lyrics, let image = previewer.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(1440.0 / 900.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(brandYellow.opacity(0.7), lineWidth: 1.5))
                }
            }
            .frame(maxWidth: 400)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            StyleViewingBanner(domain: .lyrics)
            HStack(spacing: 12) {
                Picker("Letra", selection: $model.previewWithoutLyrics) {
                    Text("Con letra").tag(false)
                    Text("Sin letra").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)

                Picker("Reproducción", selection: $model.previewPaused) {
                    Text("Suena").tag(false)
                    Text("Pausa").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)

                Button("Cambiar canción") {
                    OverlayPreview.model.previewNextSong()
                }

                if showsEntranceButton || clockCycle {
                    Button(clockCycle ? "Repetir" : "Ver la entrada") {
                        OverlayPreview.model.replayEntrance()
                    }
                }
            }
            .controlSize(.small)
            Text("Vista previa en vivo, con una canción de muestra")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - The notch

/// Which moment of the notch the preview shows.
enum NotchPreviewScene: String, CaseIterable, Identifiable {
    case closed, peek, open, volume, brightness, notification, timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed: return "Cerrado"
        case .peek: return "Canción nueva"
        case .open: return "Abierto"
        case .volume: return "Volumen"
        case .brightness: return "Brillo"
        case .notification: return "Aviso"
        case .timer: return "Temporizador"
        }
    }
}

/// The notch of the preview and what drives it.
@MainActor
@Observable
final class NotchPreviewState {
    static let shared = NotchPreviewState()

    let notch = NotchModel()
    let model = LyricsViewModel(demo: true)
    let services = NotchServices(demo: true)
    private(set) var scene: NotchPreviewScene = .open
    /// The level the volume and brightness scenes show.
    private(set) var level: Float = 0.5
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        notch.isListening = true
        model.startPreview()
        model.setNotchActive(true)
        services.agenda.prepare()
        services.system.refresh()
        show(scene)
    }

    func stop() {
        guard started else { return }
        started = false
        services.timer.reset()
        notch.reset()
        model.stopPreview()
        model.setNotchActive(false)
    }

    func show(_ next: NotchPreviewScene) {
        scene = next
        notch.close("preview")
        notch.dismissNotification()
        notch.isListening = true
        if next != .timer { services.timer.reset() }
        // A moment of calm, so the change between two scenes is seen as an animation.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard scene == next else { return }
            switch next {
            case .closed: break
            case .peek: notch.peek(for: 4)
            case .open: notch.open(tab: .home)
            case .volume: step(0, kind: .volume)
            case .brightness: step(0, kind: .brightness)
            case .timer: services.timer.start(minutes: 5)
            case .notification:
                notch.showNotification(NotchNotification(
                    id: 1, bundleID: "com.apple.MobileSMS", title: "Marta",
                    subtitle: "", body: "¿Comemos hoy? Te espero en la plaza", date: Date()
                ), for: 4)
            }
        }
    }

    /// Raises or lowers the level and shows it, the way the keys do.
    func step(_ delta: Float, kind: NotchHUD.Kind) {
        level = min(max(level + delta, 0), 1)
        notch.showHUD(NotchHUD(kind: kind, value: level), for: 2.2)
    }
}

/// The notch on a stand-in desktop: the real notch view, shrunk to fit a box.
struct NotchStage: View {
    @Bindable var state: NotchPreviewState
    var revision = 0
    let size: CGSize

    /// The box the notch needs when it is open: its size plus room for the shadow.
    static var room: CGSize {
        let open = NotchGeometry.openSize
        return CGSize(width: open.width + 96, height: open.height + 40)
    }

    var body: some View {
        let g = NotchGeometry(notch: CGSize(width: 185, height: 32))
        let scale = min(1, size.width / Self.room.width)
        ZStack(alignment: .top) {
            // A stand-in for the desktop, under the menu bar.
            LinearGradient(colors: [Color(white: 0.34), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.black.opacity(0.35)).frame(height: 24 * scale).frame(maxHeight: .infinity, alignment: .top)
            NotchView(notch: state.notch, model: state.model, services: state.services, geometry: g, revision: revision)
                .environment(\.isSettingsPreview, true)
                .frame(width: g.panelSize.width, height: g.panelSize.height, alignment: .top)
                .scaleEffect(scale, anchor: .top)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The real notch view, in a window of its own size, shrunk to fit.
struct NotchPreview: View {

    @Bindable var revision = SettingsRevision.shared
    @Bindable var state = NotchPreviewState.shared

    var body: some View {
        GeometryReader { proxy in
            NotchStage(state: state, revision: revision.value, size: proxy.size)
        }
        .frame(height: NotchStage.room.height * 0.86)
        .frame(maxWidth: 640)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .animation(.smooth(duration: 0.35), value: revision.value)
        .onAppear { state.start() }
        .onDisappear { if !SettingsPreviewSnapshot.isRunning { state.stop() } }
    }
}

/// The notch preview, with the moments to choose from and the keys that raise and
/// lower the volume.
struct NotchPreviewCard: View {

    @Bindable var state = NotchPreviewState.shared
    @Bindable var previewer = StylePreviewer.shared

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                NotchPreview()
                if previewer.domain == .notch, let image = previewer.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(brandYellow.opacity(0.7), lineWidth: 1.5))
                }
            }
            .frame(maxWidth: 640)
            StyleViewingBanner(domain: .notch)

            Picker("Momento", selection: Binding(get: { state.scene }, set: { state.show($0) })) {
                ForEach(NotchPreviewScene.allCases) { scene in
                    Text(scene.title).tag(scene)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 640)

            HStack(spacing: 10) {
                Button { state.step(-0.1, kind: state.scene == .brightness ? .brightness : .volume) } label: {
                    Image(systemName: "minus")
                }
                Text("Bajar o subir para ver el indicador")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { state.step(0.1, kind: state.scene == .brightness ? .brightness : .volume) } label: {
                    Image(systemName: "plus")
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Pictures of the previews

/// `MycSs --demo --settings-snapshot <prefix>`: draws the settings previews to PNG
/// files (the real settings window cannot be captured while the screen is
/// locked). Every style is tried and then undone, so the user's settings are left
/// as they were.
@MainActor
enum SettingsPreviewSnapshot {

    /// While the pictures are drawn, the previews are not stopped when the renderer
    /// drops them.
    nonisolated(unsafe) static var isRunning = false

    static func run(prefix: String, completion: @escaping () -> Void) {
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            let undo = PresetUndo.shared
            let defaults = UserDefaults.standard
            let before = defaults.dictionaryRepresentation()
            OverlayPreview.model.startPreview()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-default.png", width: 440)

            for preset in StylePreset.allCases {
                undo.run { preset.apply(to: AppSettings.shared) }
                try? await Task.sleep(nanoseconds: 900_000_000)
                write(OverlayPreviewCard(), "\(prefix)-overlay-\(preset.rawValue).png", width: 440)
            }
            undo.undo()
            // Without the clock, and with it back again.
            undo.run { AppSettings.shared.showClock = false }
            try? await Task.sleep(nanoseconds: 900_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-noclock.png", width: 440)
            undo.undo()
            try? await Task.sleep(nanoseconds: 900_000_000)
            write(OverlayPreviewCard(), "\(prefix)-overlay-clockback.png", width: 440)

            // The user's own styles: make, use, change, update and delete one.
            let library = StyleLibrary.shared
            let settings = AppSettings.shared
            settings.clockSize = 150
            library.draftName = "Prueba"
            library.createFromCurrent(.lyrics)
            let made = library.items(.lyrics).first { !$0.isBuiltIn }
            let madeID = made?.id ?? ""
            var ok = made?.title == "Prueba" && library.state(of: madeID, .lyrics) == .active
            settings.clockSize = 70
            ok = ok && library.state(of: madeID, .lyrics) == .modified
            library.apply(madeID, .lyrics)
            ok = ok && settings.clockSize == 150 && library.state(of: madeID, .lyrics) == .active
            library.apply("builtin.minimal", .lyrics)
            ok = ok && library.state(of: madeID, .lyrics) == .inactive && settings.showClock == false
            library.apply(madeID, .lyrics)
            ok = ok && settings.showClock == true
            library.beginEditing(madeID)
            library.editName = "Renombrada"
            library.commitRename()
            ok = ok && library.items(.lyrics).contains { $0.title == "Renombrada" }
            library.delete(madeID, .lyrics)
            ok = ok && !library.items(.lyrics).contains { !$0.isBuiltIn }
            print("settings snapshot: custom styles \(ok ? "OK" : "!! FAILED")")
            // Back to how it was.
            undo.undo()
            for key in ["clockSize", "showClock", "activeStyle.lyrics", "activeStyleValues.lyrics", "customStyles"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            OverlayPreview.model.stopPreview()

            let state = NotchPreviewState.shared
            NotchSnapshot.isActive = true
            state.start()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            for scene in NotchPreviewScene.allCases {
                state.show(scene)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                write(NotchPreviewCard(), "\(prefix)-notch-\(scene.rawValue).png", width: 700)
            }
            for look in NotchLook.allCases {
                undo.run { look.apply(to: AppSettings.shared) }
                state.show(.open)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                write(NotchPreviewCard(), "\(prefix)-notch-look-\(look.rawValue).png", width: 700)
            }
            undo.undo()

            // Every indicator, at the same value, to judge each look.
            let appSettings = AppSettings.shared
            state.show(.volume)
            for hud in AppSettings.NotchHUDStyle.allCases {
                appSettings.notchHUDStyle = hud
                state.step(0, kind: .volume)
                try? await Task.sleep(nanoseconds: 700_000_000)
                write(NotchPreviewCard(), "\(prefix)-hud-\(hud.rawValue).png", width: 700)
            }
            appSettings.notchHUDStyle = .bar
            appSettings.notchHUDNumber = .hidden
            state.step(0, kind: .volume)
            try? await Task.sleep(nanoseconds: 700_000_000)
            write(NotchPreviewCard(), "\(prefix)-hud-nonumber.png", width: 700)
            for key in ["notchHUDStyle", "notchHUDNumber"] { UserDefaults.standard.removeObject(forKey: key) }

            // A style seen without applying it: the picture changes, the settings do not.
            let viewedBefore = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("notch") || $0.key.hasPrefix("clock") }
            let previewer = StylePreviewer.shared
            if let item = StyleLibrary.shared.items(.notch).first(where: { $0.id == "builtin.showy" }) {
                state.show(.open)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                previewer.toggle(item, .notch)
                write(NotchPreviewCard(), "\(prefix)-viewing-notch.png", width: 700)
                previewer.stop()
            }
            if let item = StyleLibrary.shared.items(.lyrics).first(where: { $0.id == "builtin.frenkiieeee" }) {
                OverlayPreview.model.startPreview()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                previewer.toggle(item, .lyrics)
                write(OverlayPreviewCard(), "\(prefix)-viewing-lyrics.png", width: 440)
                previewer.stop()
                OverlayPreview.model.stopPreview()
            }
            // The change of song, with animation on (the pictures above are taken without it):
            // with lyrics to with lyrics, to none, and back.
            isRunning = false
            do {
                let m = OverlayPreview.model
                m.startPreview()
                m.previewWithoutLyrics = false
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let first = m.lyrics?.lines.first?.text
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 120_000_000)
                let leaving = m.lyricsLeaving && m.lyrics?.lines.first?.text == first && m.lyricsReveal < 1
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let arrived = m.lyrics?.lines.first?.text != first && m.lyrics != nil && m.lyricsReveal == 1 && !m.lyricsLeaving
                m.previewWithoutLyrics = true
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let gone = m.lyrics == nil && m.lyricsNotFound
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 800_000_000)
                let stillNone = m.lyrics == nil && m.lyricsReveal == 0
                m.previewWithoutLyrics = false
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                let back = m.lyrics != nil && m.lyricsReveal == 1 && !m.lyricsLeaving
                m.previewNextSong()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                print("settings snapshot: song change: old lyrics leave first \(leaving ? "OK" : "!! FAILED"), new ones arrive \(arrived ? "OK" : "!! FAILED"), none \(gone ? "OK" : "!! FAILED"), none to none \(stillNone ? "OK" : "!! FAILED"), none to lyrics \(back ? "OK" : "!! FAILED")")
                m.stopPreview()
            }
            isRunning = true

            let viewedAfter = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("notch") || $0.key.hasPrefix("clock") }
            print("settings snapshot: viewing a style does not apply it: \(NSDictionary(dictionary: viewedBefore).isEqual(to: viewedAfter) ? "OK" : "!! FAILED")")

            state.stop()
            NotchSnapshot.isActive = false
            let after = defaults.dictionaryRepresentation()
            let changed = Set(before.keys).union(after.keys).filter { !$0.hasPrefix("METAL_") && !$0.hasPrefix("NS") && (before[$0] as? NSObject) != (after[$0] as? NSObject) }
            print(changed.isEmpty
                  ? "settings snapshot: the user's settings are as they were"
                  : "settings snapshot: !! left changed: \(changed.sorted())")
            completion()
        }
    }

    private static func write<V: View>(_ view: V, _ path: String, width: CGFloat) {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .padding(12)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
