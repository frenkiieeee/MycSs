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

    /// The notch model that holds the volume indicator the preview shows.
    @MainActor
    static let hudDemo = NotchModel()

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
        model.hudSource = hudDemo
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

                if showsEntranceButton {
                    Button("Probar indicador") {
                        let next = Float(Int.random(in: 15...95)) / 100
                        let kind = [NotchHUD.Kind.volume, .brightness, .keyboard].randomElement() ?? .volume
                        OverlayPreview.hudDemo.showHUD(NotchHUD(kind: kind, value: next), for: 2.2)
                    }
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
    case closed, peek, open, volume, brightness, keyboard, notification, timer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed: return "Cerrado"
        case .peek: return "Canción nueva"
        case .open: return "Abierto"
        case .volume: return "Volumen"
        case .brightness: return "Brillo"
        case .keyboard: return "Teclado"
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
    /// Which kind of screen the preview shows: with a notch, or without (spec 017). It
    /// starts as the Mac's own screen, and can be changed to try the other.
    var showsNoNotch = !NSScreen.screens.contains(where: NotchController.hasHardwareNotch)
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
            case .keyboard: step(0, kind: .keyboard)
            case .timer: services.timer.start(minutes: 5)
            case .notification:
                notch.showNotification(NotchNotification(
                    id: 1, bundleID: "com.apple.MobileSMS", title: "Marta",
                    subtitle: "", body: "¿Comemos hoy? Te espero en la plaza", date: Date()
                ), for: 4)
            }
        }
    }

    /// What the + and - buttons move: the keyboard light in its scene, the brightness
    /// in its own, the volume in the rest.
    var hudKind: NotchHUD.Kind {
        switch scene {
        case .brightness: return .brightness
        case .keyboard: return .keyboard
        default: return .volume
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
        let g = state.showsNoNotch ? NotchGeometry.plain() : NotchGeometry(notch: CGSize(width: 185, height: 32))
        let scale = min(1, size.width / Self.room.width)
        ZStack(alignment: .top) {
            // A stand-in for the desktop, under the menu bar.
            LinearGradient(colors: [Color(white: 0.34), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.black.opacity(0.35)).frame(height: 24 * scale).frame(maxHeight: .infinity, alignment: .top)
            NotchView(notch: state.notch, model: state.model, services: state.services, geometry: g, revision: revision, isPreview: true)
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

            Picker("Pantalla", selection: $state.showsNoNotch) {
                Text("Con notch").tag(false)
                Text("Sin notch").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .help("Cómo se ve en una pantalla con notch o sin él")

            Picker("Momento", selection: Binding(get: { state.scene }, set: { state.show($0) })) {
                ForEach(NotchPreviewScene.allCases) { scene in
                    Text(scene.title).tag(scene)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 640)

            HStack(spacing: 10) {
                Button { state.step(-0.1, kind: state.hudKind) } label: {
                    Image(systemName: "minus")
                }
                Text("Bajar o subir para ver el indicador")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { state.step(0.1, kind: state.hudKind) } label: {
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
