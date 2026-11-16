import AppKit
import Observation
import SwiftUI

/// Whether the notch can read the notifications, looked at while the page is open.
@MainActor
@Observable
final class NotificationAccessStatus {
    static let shared = NotificationAccessStatus()
    private(set) var access: NotificationsModel.Access = .unknown
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        check()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let probe = NotificationsModel()
        probe.logsChanges = false
        let result = probe.checkAccess()
        if result != access { access = result }
    }
}

/// Everything about the notch, with the notch itself drawn on top.
struct NotchSettingsPage: View {
    @Bindable var settings = AppSettings.shared
    /// Settings live in `UserDefaults`, which SwiftUI does not watch: reading this
    /// redraws the page on every change, so the controls show what was clicked.
    @Bindable var revision = SettingsRevision.shared
    @Bindable var accessibility = AccessibilityStatus.shared
    @Bindable var notificationAccess = NotificationAccessStatus.shared

    var body: some View {
        let _ = revision.value
        VStack(spacing: 0) {
            NotchPreviewCard()
                .padding(.horizontal)
            Form {
                looks
                sizeAndMotion
                appearance
                music
                indicators
                widgets
                notifications
                menuBar
            }
            .formStyle(.grouped)
        }
        .onAppear { notificationAccess.start() }
        .onDisappear {
            notificationAccess.stop()
            StylePreviewer.shared.stop()
        }
    }

    // MARK: - Sections

    private var looks: some View {
        StyleListSection(domain: .notch, title: "Estilos del notch")
    }

    private var sizeAndMotion: some View {
        Section("Tamaño y movimiento") {
            HStack {
                Text("Tamaño del notch cerrado")
                Slider(value: $settings.notchClosedScale, in: 0.5...1.3)
                Text("\(Int(settings.notchClosedScale * 100)) %")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text("Tamaño del notch abierto")
                Slider(value: $settings.notchScale, in: 0.7...1.3)
                Text("\(Int(settings.notchScale * 100)) %")
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            Picker("Movimiento", selection: $settings.notchMotion) {
                ForEach(AppSettings.NotchMotionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Al abrirse", selection: $settings.notchOpenStyle) {
                ForEach(AppSettings.NotchOpenStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Canción nueva", selection: $settings.notchPeekStyle) {
                ForEach(AppSettings.NotchPeekStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if settings.notchPeekStyle == .sides {
                HStack {
                    Text("Ancho hacia los lados")
                    Slider(value: $settings.notchPeekWidth, in: 0.6...2.6)
                    Text("\(Int(settings.notchPeekWidth * 100)) %")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
            HStack {
                Text("Duración de la animación")
                Slider(value: $settings.notchPeekDuration, in: 0.2...1.8)
                Text(String(format: "%.1f s", settings.notchPeekDuration))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            HStack {
                Text("Tiempo abierto")
                Slider(value: $settings.notchPeekSeconds, in: 1.5...12)
                Text(String(format: "%.1f s", settings.notchPeekSeconds))
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }
            Text("""
            El notch cerrado solo cambia de ancho (a los lados del hueco) y de tamaño de lo que \
            lleva; el alto es el del hueco de la pantalla. El reproductor ocupa el 60 % del notch abierto y el widget de la derecha el 40 %. \
            «Primero a los lados» ensancha el notch y después lo baja, como el de boring.notch; \
            «Hacia abajo» muestra el título debajo del hueco.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        Section("Aspecto") {
            Picker("Color de acento", selection: $settings.notchAccent) {
                ForEach(AppSettings.NotchAccent.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Portada", selection: $settings.notchCoverShape) {
                ForEach(AppSettings.NotchCoverShape.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Visualizador", selection: $settings.notchVisualizerStyle) {
                ForEach(AppSettings.NotchVisualizerStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Que siga el ritmo real de la canción", isOn: $settings.notchReactive)
            Text("""
            El ritmo real escucha el audio del sistema solo mientras suena música, lo reduce a \
            cinco números y lo descarta: no graba ni envía nada. La primera vez, macOS pide el \
            permiso de grabación de audio del sistema; sin él, las barras usan la animación de siempre.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var music: some View {
        Section("Música") {
            Toggle("Mostrar el notch de MycSs", isOn: $settings.notchEnabled)
            if NSScreen.screens.count > 1 || settings.notchDisplays == .all {
                Picker("Pantallas", selection: $settings.notchDisplays) {
                    ForEach(AppSettings.NotchDisplays.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Con otra pantalla conectada, el notch también sale arriba en el centro, como una píldora. Se abre solo en la pantalla donde pones el puntero.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Toggle("Portada y visualizador a los lados mientras suena", isOn: $settings.notchWings)
            Toggle("Plegar el notch cuando no suena nada", isOn: $settings.notchHideWhenIdle)
            Toggle("Mostrar título y artista al cambiar de canción", isOn: $settings.notchPeek)
        }
    }

    private var indicators: some View {
        Section("Volumen y brillo") {
            Toggle("Mostrar el volumen y el brillo en el notch", isOn: $settings.notchHUD)
            Picker("Indicador", selection: $settings.notchHUDStyle) {
                ForEach(AppSettings.NotchHUDStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Número", selection: $settings.notchHUDNumber) {
                ForEach(AppSettings.NotchHUDNumber.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Movimiento del valor", selection: $settings.notchHUDMotion) {
                ForEach(AppSettings.NotchHUDMotion.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Entrada y salida", selection: $settings.notchHUDEntrance) {
                ForEach(AppSettings.NotchHUDEntrance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("""
            La barra, el deslizador, el anillo y el número viajan de un valor al siguiente \
            con un muelle, sin saltos: «Cuenta paso a paso» pasa por cada número, «Dígitos que \
            ruedan» los hace girar y «Oculto» quita el número. Prueba los cambios con los botones \
            + y − de la vista previa, en «Volumen» o «Brillo».
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            LabeledContent("Accesibilidad") {
                Text(accessibility.isTrusted ? "Concedida" : "Falta el permiso")
                    .foregroundStyle(accessibility.isTrusted ? Color.green : Color.orange)
            }

            if !accessibility.isTrusted {
                HStack {
                    Button("Pedir permiso…") { accessibility.request() }
                    Button("Mostrar MycSs en el Finder") { accessibility.revealApp() }
                    Button("Reparar el permiso") { accessibility.resetAndRequest() }
                }
                Text("""
                **1.** Pulsa «Pedir permiso…»: macOS enseña un aviso y abre Accesibilidad. \
                **2.** Activa MycSs en la lista; si no aparece, arrastra ahí la app con \
                «Mostrar MycSs en el Finder». **3.** Si aparece activada pero aquí sigue \
                «Falta el permiso», es una entrada de una versión anterior con otra firma: \
                «Reparar el permiso» borra solo la entrada de MycSs y vuelve a pedirla.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Text("""
            Para dibujar el volumen y el brillo en el notch, MycSs tiene que quedarse con esas \
            teclas, y eso necesita Accesibilidad. **Sin el permiso solo sale el indicador del \
            sistema**, para que nunca aparezcan los dos a la vez. Con el notch abierto, el valor \
            sale en la cabecera, junto a la pestaña.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var widgets: some View {
        Section("Widgets de la derecha") {
            ForEach(AppSettings.NotchWidget.allCases) { widget in
                Toggle(isOn: Binding(
                    get: { settings.isNotchWidgetOn(widget) },
                    set: { settings.setNotchWidget(widget, on: $0) }
                )) {
                    Label(widget.title, systemImage: widget.symbol)
                }
            }
            Text("""
            Los widgets activados se cambian con los iconos de la esquina del notch abierto. \
            El portapapeles está apagado por defecto: guarda lo último que copias (hasta 8 \
            cosas, solo mientras MycSs está abierto) y no lo envía a ningún sitio. Los \
            recordatorios y el calendario piden permiso la primera vez.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Button("Permisos de Calendarios…") { Self.openPrivacy("Calendars") }
                Button("Permisos de Recordatorios…") { Self.openPrivacy("Reminders") }
            }
        }
    }

    private var notifications: some View {
        Section("Notificaciones en el notch") {
            Toggle("Mostrar las notificaciones de otras apps", isOn: $settings.notchNotifications)

            LabeledContent("Acceso total al disco") {
                switch notificationAccess.access {
                case .granted: Text("Concedido").foregroundStyle(Color.green)
                case .denied: Text("Falta el permiso").foregroundStyle(Color.orange)
                case .unavailable: Text("No se encuentra la base de datos").foregroundStyle(Color.orange)
                case .unknown: Text("Comprobando…").foregroundStyle(.secondary)
                }
            }

            if notificationAccess.access != .granted {
                HStack {
                    Button("Abrir Acceso total al disco…") { Self.openPrivacy("AllFiles") }
                    Button("Mostrar MycSs en el Finder y copiar su ruta") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Bundle.main.bundlePath, forType: .string)
                        accessibility.revealApp()
                    }
                }
                Text("""
                **MycSs no sale en la lista hasta que la añades tú**, porque macOS solo \
                enseña ahí las apps que ya ha visto pedir ese permiso. **1.** Pulsa «Abrir \
                Acceso total al disco…». **2.** Pulsa el botón **+** debajo de la lista \
                (te pedirá tu contraseña o Touch ID). **3.** Elige MycSs: si no la ves, \
                pulsa «Mostrar MycSs en el Finder» y arrástrala a la lista, o usa ⇧⌘G en el \
                selector y pega la ruta, que se copia al pulsar ese botón. **4.** Activa el interruptor de MycSs y, si \
                macOS lo pide, «Cerrar y reabrir». El estado de arriba se actualiza solo.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Text("""
            macOS guarda las notificaciones en una base de datos protegida: MycSs la lee \
            (solo la lee) y enseña la nueva en el notch unos segundos; apuntarla con el ratón \
            la mantiene y un clic abre la app. **No puede ocultar el aviso del sistema**: \
            macOS lo dibuja por su cuenta. Para verlo solo en el notch, en Ajustes del Sistema › \
            Notificaciones pon el estilo de aviso en «Ninguno» en las apps que quieras; \
            las notificaciones siguen llegando al Centro de notificaciones y MycSs las ve. \
            Tras conceder el permiso, cierra y abre MycSs.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Abrir Notificaciones…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var menuBar: some View {
        Section("Barra de menú") {
            Toggle("Ocultar el icono de MycSs mientras el notch está activo", isOn: $settings.hideMenuBarIcon)
            Text("""
            Con el notch encendido, el engranaje de su esquina abre estos ajustes, y volver \
            a abrir MycSs desde el Finder o Spotlight también. Si apagas el notch, el icono \
            vuelve solo para que no te quedes sin acceso.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private static func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
