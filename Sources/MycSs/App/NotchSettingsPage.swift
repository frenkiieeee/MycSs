import AppKit
import Observation
import SwiftUI

/// The part of the notch settings that is open. It lives in an observable object
/// because `@State` is not available in this build.
@Observable
final class NotchSettingsNav {
    static let shared = NotchSettingsNav()

    enum Tab: String, CaseIterable, Identifiable {
        case styles, look, music, indicators, widgets, notifications, system

        var id: String { rawValue }
        var title: String {
            switch self {
            case .styles: return "Estilos"
            case .look: return "Aspecto"
            case .music: return "Música"
            case .indicators: return "Teclas"
            case .widgets: return "Widgets"
            case .notifications: return "Avisos"
            case .system: return "Sistema"
            }
        }
    }

    var tab: Tab = .styles
}

/// Everything about the notch, with the notch itself drawn on top.
struct NotchSettingsPage: View {
    @Bindable var nav = NotchSettingsNav.shared
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
                master
                Picker("Parte", selection: $nav.tab) {
                    ForEach(NotchSettingsNav.Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch nav.tab {
                case .styles:
                    looks
                case .look:
                    sizeAndMotion
                    openAndClose
                    appearance
                case .music:
                    music
                case .indicators:
                    indicators
                    keyboardLight
                case .widgets:
                    widgets
                case .notifications:
                    notifications
                    systemBanners
                case .system:
                    menuBar
                }
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

    /// The switch for the whole notch, and where it shows. Always on top.
    private var master: some View {
        Section("Notch") {
            Toggle("Mostrar el notch de MycSs", isOn: $settings.notchEnabled)
            if NSScreen.screens.count > 1 || settings.notchDisplays == .all {
                Picker("Pantallas", selection: $settings.notchDisplays) {
                    ForEach(AppSettings.NotchDisplays.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Con otra pantalla conectada, el notch también sale arriba en el centro, como una píldora. Se abre solo en la pantalla donde pones el puntero.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// How fast it opens and closes, and what a drag of files does (spec 013).
    private var openAndClose: some View {
        Section("Apertura y cierre") {
            Picker("Abrir", selection: $settings.notchOpenTrigger) {
                ForEach(AppSettings.NotchOpenTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if settings.notchOpenTrigger == .hover {
                seconds("Esperar antes de abrir", value: $settings.notchOpenDelay, in: 0...1)
            }
            seconds("Esperar antes de cerrar", value: $settings.notchCloseDelay, in: 0...2)

            Toggle("Abrir la bandeja al arrastrar archivos", isOn: $settings.notchDragOpen)
            if settings.notchDragOpen {
                seconds("Mantener los archivos encima", value: $settings.notchDragDelay, in: 0...1.5)
                Picker("Zona de arrastre", selection: $settings.notchDragZone) {
                    ForEach(AppSettings.NotchDragZone.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Text("""
            Con «Con un clic» el notch solo se abre al pulsarlo. La bandeja se abre cuando \
            arrastras archivos y los mantienes sobre el notch el tiempo elegido; un clic \
            sostenido o un arrastre de otra cosa ya no la abren.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func seconds(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.05) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range, step: step)
            Text(String(format: "%.2f s", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var music: some View {
        Section("Música") {
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
            + y − de la vista previa, en «Volumen», «Brillo» o «Teclado».
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

    /// The shortcut that moves the keyboard light (spec 011).
    private var keyboardLight: some View {
        Section("Luz del teclado") {
            Toggle("Subir y bajar la luz del teclado con un atajo", isOn: $settings.keyboardLightEnabled)
                .disabled(!keyboardLightAvailable)

            if keyboardLightAvailable {
                LabeledContent("Subir") {
                    ChordRecorder(chord: settings.keyboardLightUp) { settings.keyboardLightUp = $0 }
                        .frame(width: 150, height: 26)
                }
                LabeledContent("Bajar") {
                    ChordRecorder(chord: settings.keyboardLightDown) { settings.keyboardLightDown = $0 }
                        .frame(width: 150, height: 26)
                }
                .disabled(!settings.keyboardLightEnabled)

                HStack {
                    Button("Restaurar ⌥F2 y ⌥F1") { settings.resetKeyboardLightShortcuts() }
                        .disabled(settings.keyboardLightUp == KeyboardLightDirection.defaultUp
                                  && settings.keyboardLightDown == KeyboardLightDirection.defaultDown)
                    Spacer()
                    Text(accessibility.isTrusted ? "Accesibilidad concedida" : "Falta Accesibilidad")
                        .font(.callout)
                        .foregroundStyle(accessibility.isTrusted ? Color.green : Color.orange)
                }
                .disabled(!settings.keyboardLightEnabled)
            } else {
                Text("Este Mac no tiene luz de teclado que MycSs pueda mover.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("""
            Por defecto, **⌥F2** sube la luz y **⌥F1** la baja, en pasos de 1/16, y el cambio sale en \
            el notch con el mismo indicador del volumen y el brillo (su estilo, número y animación \
            son los de arriba; en el bloqueo, la animación que elijas en «Apariencia»). Pulsa un \
            atajo y teclea otro para cambiarlo; con las teclas de brillo vale también. Mientras \
            esté activo, ⌥F1 y ⌥F2 ya no abren los ajustes de Pantallas. Necesita Accesibilidad, \
            igual que el volumen y el brillo, y el notch encendido.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var keyboardLightAvailable: Bool { KeyboardBacklight.isAvailable }

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
                HStack(spacing: 10) {
                    switch notificationAccess.access {
                    case .granted: Text("Concedido").foregroundStyle(Color.green)
                    case .denied: Text("Falta el permiso").foregroundStyle(Color.orange)
                    case .unavailable: Text("No se encuentra la base de datos").foregroundStyle(Color.orange)
                    case .unknown: Text("Comprobando…").foregroundStyle(.secondary)
                    }
                    if notificationAccess.access != .granted {
                        Button("Conceder…") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Bundle.main.bundlePath, forType: .string)
                            Self.openPrivacy("AllFiles")
                            accessibility.revealApp()
                        }
                    }
                }
            }
            if notificationAccess.access != .granted {
                DisclosureGroup("Cómo conceder el permiso") {
                    Text("""
                    «Conceder…» abre Acceso total al disco y enseña MycSs en el Finder (su ruta \
                    queda copiada). Pulsa **+** bajo la lista, elige MycSs (o arrástrala, o usa \
                    ⇧⌘G y pega la ruta) y activa su interruptor. El estado de arriba cambia solo.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            seconds("Tiempo en el notch", value: $settings.notchNotificationSeconds, in: 2...12, step: 0.5)
            Toggle("Mostrar el contenido", isOn: $settings.notchNotificationShowBody)
            Toggle("Historial en el notch abierto", isOn: Binding(
                get: { settings.isNotchWidgetOn(.notifications) },
                set: { settings.setNotchWidget(.notifications, on: $0) }
            ))
            Text("""
            Salen en el notch en cuanto llegan; varias seguidas de la misma app se cuentan. \
            Apuntar una con el ratón la mantiene y un clic abre la app. Sin el contenido, solo \
            se ve qué app avisa. El historial vive en la memoria y se borra al salir.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// Where each app's notifications are seen, and the system's banner (spec 012).
    private var systemBanners: some View {
        Section("Dónde se ven") {
            Picker("Para las apps nuevas", selection: $settings.notchNotificationDefault) {
                ForEach(AppSettings.NotificationRule.allCases) { Text($0.title).tag($0) }
            }
            let rules = notificationAccess.apps.map { settings.notificationRule(for: $0) } + [settings.notchNotificationDefault]
            if rules.contains(where: \.hidesBanner), !accessibility.isTrusted {
                LabeledContent("Accesibilidad") {
                    HStack(spacing: 10) {
                        Text("Falta para «Solo notch»").foregroundStyle(Color.orange)
                        Button("Pedir permiso…") { accessibility.request() }
                    }
                }
            }
            ForEach(notificationAccess.apps.prefix(14), id: \.self) { bundle in
                Picker(selection: Binding(
                    get: { settings.notificationRule(for: bundle) },
                    set: { settings.setNotificationRule($0, for: bundle) }
                )) {
                    ForEach(AppSettings.NotificationRule.allCases) { Text($0.title).tag($0) }
                } label: {
                    HStack(spacing: 8) {
                        if let icon = NotchNotification.icon(for: bundle) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(NotchNotification.appName(for: bundle))
                    }
                }
            }
            if notificationAccess.apps.isEmpty, notificationAccess.access == .granted {
                Text("Las apps aparecerán aquí cuando manden notificaciones.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("""
            **Solo notch** cierra el aviso lateral de macOS en cuanto la notificación sale en \
            el notch, mientras MycSs está activo (experimental: también la quita del Centro de \
            notificaciones). **Solo sistema** deja la app fuera del notch. Cambia una app y \
            las demás siguen la regla de las apps nuevas.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
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
