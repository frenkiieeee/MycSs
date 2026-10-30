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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MycSs — Preferencias"
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

/// The settings interface.
struct SettingsView: View {

    @Bindable var settings = AppSettings.shared

    var body: some View {
        TabView {
            LyricsSettingsTab()
                .tabItem { Label("Letras", systemImage: "text.quote") }
            AppearanceSettingsTab()
                .tabItem { Label("Apariencia", systemImage: "paintbrush") }
            BehaviourSettingsTab()
                .tabItem { Label("Comportamiento", systemImage: "gearshape") }
        }
        .frame(width: 720, height: 640)
    }
}

// MARK: - Lyrics

struct LyricsSettingsTab: View {
    @Bindable var settings = AppSettings.shared
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
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
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
        .padding()
    }
}

// MARK: - Behaviour

struct BehaviourSettingsTab: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Overlay") {
                Toggle("Mostrar letras en la pantalla de bloqueo", isOn: $settings.overlayEnabled)
            }

            Section("Pantalla") {
                Picker("Comportamiento", selection: $settings.displayMode) {
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
                letras. En modo «apagar», el sistema apaga la pantalla pasado el \
                tiempo indicado.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
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
