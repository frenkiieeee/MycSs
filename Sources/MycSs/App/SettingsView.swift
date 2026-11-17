import AppKit
import Observation
import SwiftUI

/// The settings window.
///
/// A plain `NSWindow` hosting a SwiftUI view: the app is an agent without a
/// Dock icon, so there is no `Settings` scene to attach to.
///
/// **Why no `@State`**: the project builds with the Command Line Tools, which do
/// not ship the `SwiftUIMacros` plugin that `@State` needs. `@Bindable` over an
/// `@Observable` class works with the plugins that are present, and it is also
/// the better fit here: the settings object is shared, so a change made in the
/// panel is visible to the overlay immediately.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    static let shared = SettingsWindowController()

    /// Opens the settings window, bringing it to the front if it is already open.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MycSs"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// The sections of the sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, styles, notch, lyrics, clock, appearance, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .styles: return "Estilos"
        case .notch: return "Notch"
        case .lyrics: return "Letras"
        case .clock: return "Reloj"
        case .appearance: return "Apariencia"
        case .about: return "Acerca de"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .styles: return "wand.and.stars"
        case .notch: return "rectangle.topthird.inset.filled"
        case .lyrics: return "text.quote"
        case .clock: return "clock"
        case .appearance: return "paintbrush"
        case .about: return "pawprint"
        }
    }
}

/// Which section is open. A shared object because `@State` is not available in
/// this build.
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var selection: SettingsSection? = .general
}

/// The brand yellow, `#FFD400`.
let brandYellow = Color(red: 1.0, green: 0.831, blue: 0.0)

/// A mascot picture from the app bundle, or a note symbol when running without
/// one (a plain `swift build` has no bundle resources).
struct MascotImage: View {
    let name: String

    static func load(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Mascot"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(contentsOfFile: "Assets/Mascot/png/\(name).png")
    }

    var body: some View {
        // From the app bundle, or from the repository when running with a plain
        // `swift build`, which has no bundle resources.
        if let image = Self.load(name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(8)
        }
    }
}

/// The settings interface: a sidebar with the sections and the page of the one
/// that is open.
struct SettingsView: View {

    @Bindable var nav = SettingsNavigation.shared
    @Bindable var revision = SettingsRevision.shared

    var body: some View {
        let _ = revision.value
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $nav.selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    MascotImage(name: "mycss-feliz-512")
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("MycSs")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                        Text("Frenkiieeee")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Salir de MycSs", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
            switch nav.selection ?? .general {
            case .general: GeneralSettingsPage()
            case .styles: StylesSettingsPage()
            case .notch: NotchSettingsPage()
            case .lyrics: LyricsSettingsTab()
            case .clock: ClockSettingsPage()
            case .appearance: AppearanceSettingsTab()
            case .about: AboutSettingsPage()
            }
        }
        .tint(brandYellow)
        .frame(minWidth: 780, minHeight: 560)
    }
}

// MARK: - Lyrics

struct LyricsSettingsTab: View {
    @Bindable var settings = AppSettings.shared
    /// Settings live in `UserDefaults`, which SwiftUI does not watch: reading this
    /// redraws the page on every change, so the controls show what was clicked.
    @Bindable var revision = SettingsRevision.shared
    /// The search text for the font list. It lives on the shared settings object
    /// because `@State` needs the SwiftUI macros plugin, which the Command Line
    /// Tools do not ship.
    @Bindable var filter = FontFilter.shared

    private var filteredFonts: [SystemFonts.Entry] {
        guard !filter.text.isEmpty else { return SystemFonts.all() }
        let needle = filter.text.lowercased()
        return SystemFonts.all().filter {
            $0.displayName.lowercased().contains(needle)
        }
    }

    var body: some View {
        let _ = revision.value
        VStack(spacing: 0) {
            OverlayPreviewCard()
                .padding(.horizontal)
            Form {
                Section("Fuente") {
                    TextField("Buscar fuente", text: $filter.text)
                        .textFieldStyle(.roundedBorder)

                    Picker("Tipo de letra", selection: $settings.fontName) {
                        ForEach(filteredFonts.prefix(300)) { entry in
                            Text(entry.displayName).tag(entry.postScriptName)
                        }
                    }

                    HStack {
                        Text("Tamaño")
                        Slider(value: $settings.fontSize, in: 18...96)
                        Text("\(Int(settings.fontSize))")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }

                    LabeledContent("Vista previa") {
                        Text("Así se van a ver las letras")
                            .font(Font(settings.lyricsFont))
                            .lineLimit(1)
                    }
                }

                Section("Resaltado") {
                    Picker("Efecto", selection: $settings.lyricEffect) {
                        ForEach(AppSettings.LyricEffect.allCases, id: \.self) { effect in
                            Text(effect.title).tag(effect)
                        }
                    }

                    Text("""
                    «Línea completa» marca la línea que se está cantando completa, \
                    sin seguir palabra por palabra. «Palabra a palabra» ilumina la \
                    palabra exacta. «Palabra destacada» además agranda la palabra que \
                    se está cantando.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Section("Profundidad") {
                    Toggle("Reducir y desenfocar las líneas lejanas, como Apple Music", isOn: $settings.lyricsDepth)
                }

                Section("Timing de las palabras") {
                    Picker("Distribución", selection: $settings.wordTiming) {
                        ForEach(AppSettings.WordTiming.allCases, id: \.self) { timing in
                            Text(timing.title).tag(timing)
                        }
                    }

                    Text("""
                    «Proporcional a la letra» reparte el tiempo según el tamaño de \
                    cada palabra, y las pausas quedan vacías: la letra termina de \
                    iluminarse cuando termina de cantarse, en vez de avanzar lento \
                    durante el silencio.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Section("Cambio de canción") {
                    Picker("Animación", selection: $settings.songTransition) {
                        ForEach(AppSettings.SongTransition.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    if settings.songTransition != .off {
                        HStack {
                            Text("Duración")
                            Slider(value: $settings.songTransitionSeconds, in: 0.25...1.8)
                            Text(String(format: "%.1f s", settings.songTransitionSeconds))
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                    }

                    Text("""
                    Al pasar a otra canción, la letra vieja sale, la portada nueva entra \
                    sobre la anterior, el título cambia y la letra nueva entra desde abajo. \
                    Si una de las dos no tiene letra, la portada se mueve al centro o \
                    vuelve a su sitio sin cortes. Usa «Cambiar canción» en la vista previa \
                    para verlo, y «Con letra» y «Sin letra» para ver cada caso.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @Bindable var settings = AppSettings.shared
    /// Settings live in `UserDefaults`, which SwiftUI does not watch: reading this
    /// redraws the page on every change, so the controls show what was clicked.
    @Bindable var revision = SettingsRevision.shared

    var body: some View {
        let _ = revision.value
        VStack(spacing: 0) {
            OverlayPreviewCard(showsEntranceButton: true)
                .padding(.horizontal)
            Form {
                Section("Fondo") {
                    Picker("Estilo", selection: $settings.backgroundMode) {
                        ForEach(BackgroundView.Mode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("Usar los colores del álbum", isOn: $settings.useArtworkColours)

                    Text("""
                    Con esta opción apagada se usa un color fijo en lugar del que \
                    viene de la portada.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Velocidad")
                        Slider(value: $settings.animationIntensity, in: 0...2)
                        Text(String(format: "%.1fx", settings.animationIntensity))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Text("Transición entre canciones")
                        Slider(value: $settings.crossFadeSeconds, in: 0...4)
                        Text(String(format: "%.1fs", settings.crossFadeSeconds))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Section("Aparición") {
                    Picker("Entrada", selection: $settings.entranceAnimation) {
                        ForEach(AppSettings.Entrance.allCases, id: \.self) { entrance in
                            Text(entrance.title).tag(entrance)
                        }
                    }

                    Text("""
                    Define cómo aparece la app sobre la pantalla de bloqueo, para \
                    que no salte de golpe.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Section("Contenido") {
                    Toggle("Mostrar el reloj", isOn: $settings.showClock)
                    Toggle("Mostrar la portada del álbum", isOn: $settings.showArtwork)
                    Toggle("Mostrar título y artista", isOn: $settings.showTrackInfo)
                    Toggle("Mostrar el reproductor (anterior, pausa, siguiente y progreso)", isOn: $settings.showPlayerControls)
                    Toggle("Centrar la portada cuando la canción no tiene letra", isOn: $settings.centerCoverWithoutLyrics)
                    Toggle("Portada a la derecha y letra a la izquierda", isOn: $settings.coverOnRight)

                    HStack {
                        Text("Tamaño de la portada")
                        Slider(value: $settings.artworkSize, in: 160...700)
                        Text("\(Int(settings.artworkSize))")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - General

struct GeneralSettingsPage: View {
    @Bindable var settings = AppSettings.shared
    @Bindable var login = LaunchAtLogin.shared
    @Bindable var undo = PresetUndo.shared
    /// Settings live in `UserDefaults`, which SwiftUI does not watch: reading this
    /// redraws the page on every change, so the controls show what was clicked.
    @Bindable var revision = SettingsRevision.shared
    var body: some View {
        let _ = revision.value
        Form {
            Section("Reproductor") {
                Picker("Seguir a", selection: $settings.playerPreference) {
                    ForEach(PlayerHub.Preference.allCases, id: \.self) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text("""
                En «Automático» MycSs sigue al reproductor que esté sonando, y se \
                queda con el mismo mientras siga sonando. macOS pide permiso la \
                primera vez que lee Spotify o Apple Music.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Letras en pantalla completa") {
                LabeledContent("Atajo de teclado") {
                    HotKeyRecorder()
                        .frame(width: 150, height: 26)
                }

                Picker("Abrir solas tras", selection: $settings.idleMinutes) {
                    Text("Nunca").tag(0)
                    ForEach([1, 2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text("\(minutes) min sin usar la Mac").tag(minutes)
                    }
                }

                Toggle("Salir con Esc o con un clic fuera de las letras", isOn: $settings.dismissOnEscapeOrClick)

                Text("""
                Funciona como un salvapantallas: las letras cubren el escritorio. \
                Se abren con el atajo o desde el menú de la barra, en «Letras», y se \
                cierran con Esc, con un clic fuera de las letras o con el mismo \
                atajo. Si se abren solas por inactividad, se cierran con cualquier \
                tecla o movimiento del ratón. En la pantalla de bloqueo, Esc o un \
                clic fuera de las letras dejan ver la pantalla de bloqueo normal \
                hasta el siguiente bloqueo.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Inicio") {
                Toggle("Abrir MycSs al iniciar sesión", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.set($0) }
                ))
                .disabled(!login.isAvailable)
                if let message = login.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Restaurar valores") {
                HStack {
                    Button("Letras y reloj") { SettingsReset.reset([.lyrics]) }
                    Button("Notch") { SettingsReset.reset([.notch]) }
                    Button("Todo") { SettingsReset.reset([.lyrics, .notch]) }
                    Spacer()
                    if undo.canUndo {
                        Button("Deshacer") { undo.undo() }
                    }
                }
                Text("""
                Vuelve a los valores de fábrica de la apariencia de las letras, el reloj \
                y el notch. No toca tus estilos guardados, el atajo ni la energía, y \
                «Deshacer» lo deja como estaba.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Pantalla de bloqueo") {
                Toggle("Mostrar letras al bloquear la Mac", isOn: $settings.overlayEnabled)

                Picker("Pantalla", selection: $settings.displayMode) {
                    ForEach(AppSettings.DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if settings.displayMode == .sleepAfterMinutes {
                    Picker("Minutos", selection: $settings.sleepAfterMinutes) {
                        ForEach([1, 5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }

                Text("""
                En modo «mantener», la pantalla queda encendida mostrando las \
                letras. En modo «apagar», el sistema la apaga pasado el tiempo \
                indicado. Esto vale también para las letras en pantalla completa.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { login.refresh() }
    }
}

// MARK: - Styles

struct StylesSettingsPage: View {

    var body: some View {
        VStack(spacing: 0) {
            OverlayPreviewCard()
                .padding(.horizontal)
            Form {
                StyleListSection(domain: .lyrics, title: "Estilos de las letras")
            }
            .formStyle(.grouped)
        }
        .onDisappear { StylePreviewer.shared.stop() }
    }
}

// MARK: - Clock

struct ClockSettingsPage: View {
    @Bindable var settings = AppSettings.shared
    /// Settings live in `UserDefaults`, which SwiftUI does not watch: reading this
    /// redraws the page on every change, so the controls show what was clicked.
    @Bindable var revision = SettingsRevision.shared

    var body: some View {
        let _ = revision.value
        VStack(spacing: 0) {
            OverlayPreviewCard(clockCycle: true)
                .padding(.horizontal)
            Form {
                Section("Reloj") {
                    Toggle("Mostrar el reloj", isOn: $settings.showClock)
                    Toggle("Mostrar la fecha", isOn: $settings.clockShowDate)

                    Picker("Alineación", selection: $settings.clockAlignment) {
                        ForEach(AppSettings.ClockAlignment.allCases, id: \.self) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }

                    HStack {
                        Text("Tamaño")
                        Slider(value: $settings.clockSize, in: 48...200)
                        Text("\(Int(settings.clockSize))")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                Section("Ocultar el reloj") {
                Toggle("Quitar el reloj unos segundos después de abrir las letras", isOn: $settings.clockAutoHide)
                if settings.clockAutoHide {
                    HStack {
                        Text("Tiempo antes de quitarlo")
                        Slider(value: $settings.clockAutoHideSeconds, in: 1...30, step: 1)
                        Text("\(Int(settings.clockAutoHideSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle("Que vuelva al mover el ratón", isOn: $settings.clockRevealOnMove)
                }
                Text("""
                Con las letras en pantalla, el reloj se va suavemente tras el tiempo \
                elegido y todo lo demás sube a su sitio. «Repetir» en la vista previa \
                lo enseña. Para no tener reloj nunca, apaga «Mostrar el reloj».
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section("Tipografía") {
                    Picker("Familia", selection: $settings.clockDesign) {
                        ForEach(AppSettings.ClockDesign.allCases, id: \.self) { design in
                            Text(design.title).tag(design)
                        }
                    }
                    Picker("Grosor", selection: $settings.clockWeight) {
                        ForEach(AppSettings.ClockWeight.allCases, id: \.self) { weight in
                            Text(weight.title).tag(weight)
                        }
                    }
                    Picker("Color", selection: $settings.clockColor) {
                        ForEach(AppSettings.ClockColor.allCases, id: \.self) { color in
                            Text(color.title).tag(color)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - About

struct AboutSettingsPage: View {
    @Bindable var updates = UpdateChecker.shared

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            MascotImage(name: "mycss-state-auriculares-512")
                .frame(width: 180, height: 180)
            Text("MycSs")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("Versión \(AppVersion.display)")
                .foregroundStyle(.secondary)
            Text("Una capa creativa para tu Mac, por Frenkiieeee.")
                .foregroundStyle(.secondary)

            updateRow

            HStack {
                Button("Permisos de Automatización…") {
                    if let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Abrir el registro") {
                    NSWorkspace.shared.open(URL(fileURLWithPath:
                        NSHomeDirectory() + "/Library/Logs/MycSs.log"))
                }
                Button("GitHub") {
                    if let url = URL(string: AppVersion.repository) { NSWorkspace.shared.open(url) }
                }
            }
            .padding(.top, 8)

            Button("Salir de MycSs", role: .destructive) { NSApp.terminate(nil) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// The button that asks GitHub for the latest release, and what it answered.
    @ViewBuilder
    private var updateRow: some View {
        VStack(spacing: 6) {
            switch updates.state {
            case .idle, .upToDate, .failed:
                Button("Buscar actualizaciones") { updates.check() }
            case .checking:
                ProgressView().controlSize(.small)
            case .available(let version, let url):
                Button("Descargar \(version)") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
            switch updates.state {
            case .upToDate:
                Text("Tienes la última versión.").font(.callout).foregroundStyle(.secondary)
            case .available(let version, _):
                Text("Hay una versión nueva: \(version).").font(.callout).foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason).font(.callout).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}

/// The text typed in the font search field.
///
/// A separate observable object because `@State` is not available in this build
/// (the SwiftUI macros plugin ships with Xcode, not with the Command Line
/// Tools).
@Observable
final class FontFilter {
    static let shared = FontFilter()
    var text: String = ""
}
