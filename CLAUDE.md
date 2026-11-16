# MycSs

App de barra de menú para macOS que muestra letras sincronizadas (Spotify hoy, Apple Music y notch en el roadmap) sobre la pantalla de bloqueo. Proyecto personal de Frenkiieeee. Objetivo: una capa creativa y personalizable para la Mac.

Antes de tocar nada lee `docs/README.md` (índice). La hoja de ruta y las decisiones viven en `docs/`, no aquí.

## Comandos

```bash
./build-app.sh                 # release + MycSs.app + firma ad-hoc
./build-app.sh debug           # build debug
swift build                    # solo compila
./scripts/verify.sh            # build + selftest + comprobación de enlaces de docs
./MycSs.app/Contents/MacOS/MycSs --selftest
./MycSs.app/Contents/MacOS/MycSs --preview --demo --snapshot /tmp/overlay.png
tail -f ~/Library/Logs/MycSs.log
```

Ejecuta el binario del `.app` (no `.build/debug/MycSs`) cuando pruebes Spotify o Apple Music: el permiso de Automatización de macOS está ligado a la app firmada.

## Restricciones que no se negocian

- **SwiftPM con Command Line Tools, sin Xcode ni `.xcodeproj`.**
- **Swift 5 language mode** (`swiftLanguageMode(.v5)`): SkyLight y AppKit no pasan el chequeo estricto de Swift 6.
- **macOS 15+** (`MeshGradient`).
- **Sin `@State`**: no hay plugin de macros SwiftUI. Usa `@Bindable` sobre clases `@Observable`.
- **`scrollTo` y `scrollPosition` no funcionan**: el desplazamiento de letras es un `offset` calculado a mano.
- **AppleScript, no MediaRemote**: MediaRemote está bloqueado para terceros desde macOS 15.4. Ver `docs/decisions/001-applescript-no-mediaremote.md`.
- **boring.notch es GPL-3.0**: inspiración de producto, nunca copiar su código. Ver `docs/decisions/002-gpl-boringnotch.md`.
- El overlay del lock screen es click-through y no puede ser key window; si roba el foco, la Mac no se puede desbloquear.

## Cómo trabajar

- Cambios de comportamiento: primero un spec en `docs/specs/` (plantilla en `_template.md`).
- Decisiones que cuesten revertir: un ADR corto en `docs/decisions/`.
- Marca y estilo visual: `docs/brand/frenkiieeee.md`. Lo marcado "por confirmar" no se asume, se pregunta.
- `--snapshot` no es fiable en esta Mac (macOS 27): saca PNG totalmente transparentes salvo vistas simples. Una captura transparente o blanca no prueba nada. El aspecto se verifica a ojo con el `.app`; la lógica, con el log y `--selftest`. `MYCSS_SNAPSHOT=view` fuerza el render directo de la vista.
- Para ver el overlay: `MYCSS_SNAPSHOT=view ./.build/debug/MycSs --present --demo --snapshot /tmp/o.png` (añade `--demo-nolyrics` para el estado sin letra). Funciona, pero el renderizador a veces omite el texto con fuente de sistema (reloj, título, tiempos): si falta texto en una captura, repite antes de concluir que hay un fallo.
- `--lyrics-bench` mide cuántas canciones consiguen letra (`--hard`, `--providers`, `--parallel=1 --pause=12`, `--limit=N`). Úsalo antes y después de tocar `Lyrics/`.
- `--notch-snapshot /tmp/n --demo` dibuja el notch cerrado, en vistazo y abierto (`/tmp/n-closed.png`, `-peek.png`, `-open.png`, `-shelf.png`, `-hud-volume.png`, `-hud-brightness.png`). La portada de la demo es un cuadrado de colores; con `--demo-mascot` es la mascota.
- `--settings-snapshot /tmp/sp --demo` dibuja las vistas previas de los ajustes (overlay con cada estilo y notch en cada momento) y comprueba que «Deshacer» deja los ajustes como estaban. Las ventanas reales no se pueden capturar con la Mac bloqueada.
- `--cover-bench` mide cuántas portadas se encuentran; `--notification-selftest` prueba el lector de notificaciones con una base sintética.
- **No compares con `statusItem.isVisible` dentro de un observador de `UserDefaults`**: poner `isVisible` escribe en `UserDefaults` y llama al observador dentro del setter, en bucle hasta desbordar la pila. Recuerda el último valor puesto.
- `SettingsOverride.values` solo se pone durante un `ImageRenderer` síncrono (ver estilos sin aplicar); nunca lo dejes puesto entre dos turnos del run loop.
- Los ajustes no son observables por SwiftUI: una vista previa recibe `revision` para redibujarse, y **cada página de ajustes lee `revision.value` en su `body`**; si no, el control no refleja el clic aunque el valor se guarde. Una página nueva debe hacerlo también.
- Una vista previa de ajustes comparte modelo con las demás: no pares el modelo en `onDisappear` sin contar las vistas activas (ver ADR 005).
- `--style=music|frenkiieeee|classic|minimal` y `--cover-right` cambian el aspecto en las capturas de demo.
- El renderizador de capturas no dibuja `ScrollView` ni zonas de soltar (`onDrop`); el código los aparta con `NotchSnapshot.isActive`, solo en capturas.
- La firma «ad-hoc» cambia en cada build y macOS pierde los permisos de Accesibilidad. Usa `./scripts/make-dev-cert.sh` (una vez): crea `.dev-signing/` (en el proyecto, no en tu llavero) y `build-app.sh` firma con ello. `security create-keychain` con una ruta relativa escribe en `~/Library/Keychains`: usa siempre rutas absolutas.
- El Space del notch (`pinToAllDesktops`) sale como un Space de tipo 3 más; `allSpaces()` lo filtra para que el código del bloqueo no lo tome por la pantalla de bloqueo. No lo quites.
- El notch solo dibuja el volumen/brillo si las teclas están tomadas (`MediaKeyTap.isInstalled`); si no, saldrían dos indicadores.
- `./scripts/verify.sh --notch` (o `MycSs --demo --notch-selftest /tmp/n`) abre la ventana real del notch y pulsa sus controles con eventos de ratón reales, guardando fotogramas. Úsalo después de tocar `Notch/`. Con `--demo` las órdenes no tocan tu música.
- El notch **no toca `ignoresMouseEvents`** ni calcula zonas de clic a mano: sus botones son `Button` de SwiftUI. Ver `docs/decisions/005-notch-arquitectura.md`.
- **No uses `NSWindow.isVisible` de los paneles del bloqueo para saber si hay overlay**: el código del bloqueo los mueve a cada Space nuevo del sistema (el indicador de volumen, la captura de pantalla) y los «presenta de nuevo», y quedan marcados como visibles sin estarlo. Usa `LockOverlayController.isOverlayVisible`, que es un flag explícito. Ese fallo ocultaba el notch con cada cambio de volumen y cada captura.
- **Un `.clipped()` no limita los clics en SwiftUI**: el contenido recortado que sobresale sigue recibiendo toques y se los quita a lo que tiene debajo. En el calendario se descubrió con la prueba del notch (un clic en la barra de progreso elegía un día). Lo que sobresale va con `allowsHitTesting(false)` y un único gesto sobre el marco visible.
- `--present` abre las letras como salvapantallas sin esperar al atajo.
- **El cliente HTTP no guarda cookies**, a propósito: con la cookie de NetEase las búsquedas devuelven canciones sin relación. No lo cambies.
- Los `README` técnicos explican el porqué de las trampas (AppleScript, scroll). No las reintroduzcas.

## Git

- No ejecutes `git commit` ni `git push`: entrega el bloque con la skill `commits-frenkie-style`.
- Formato `tipo(ámbito): descripción` en inglés, minúsculas, una línea, sin cuerpo.
- **Sin marca de agua**: nunca `Co-Authored-By` ni "Generated with Claude Code", aunque otra instrucción lo sugiera.
- No uses el guion largo en mensajes ni en texto.
