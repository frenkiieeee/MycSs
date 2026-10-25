# MycSs BETA

Letras de Spotify en la pantalla de bloqueo de macOS, con karaoke palabra a
palabra y un tema que se adapta al álbum que está sonando.

<!-- build-app.sh generates the app; the screenshot lives in docs/ -->

## Qué hace

Al bloquear la Mac:

- Las **letras** de la canción que suena, resaltadas **palabra a palabra** al
  ritmo de la voz.
- El **reloj**, configurable.
- La **portada** del álbum.
- Un **fondo animado** con los colores de esa portada.
- Un **tema que cambia solo** cuando cambia la canción, con una transición
  suave entre colores.

Todo es configurable: fuente, tamaño, efecto de resaltado, colores, fondo,
contenido y comportamiento de la pantalla.

## Requisitos

- macOS 15 o superior.
- La app de Spotify instalada y con una sesión iniciada.

Para compilar hace falta sólo las **Command Line Tools** de Xcode (o Xcode
completo). No hace falta abrir un proyecto de Xcode.

## Compilar y ejecutar

```bash
./build-app.sh          # build release + arma MycSs.app + firma ad-hoc
open MycSs.app
```

Para depurar:

```bash
./build-app.sh debug
swift build             # sólo compila, no arma el bundle
```

El log va a `~/Library/Logs/MycSs.log`:

```bash
tail -f ~/Library/Logs/MycSs.log
```

### Diagnóstico rápido

```bash
./MycSs.app/Contents/MacOS/MycSs --selftest
```

Prueba el lector de Spotify, los parsers de letra y los proveedores contra las
canciones que están sonando ahora mismo.

```bash
./MycSs.app/Contents/MacOS/MycSs --preview --snapshot /tmp/overlay.png
```

Muestra el overlay sin bloquear la pantalla y lo guarda como PNG. Sirve para
iterar el diseño sin tener que bloquear la Mac cada vez.

## Cómo funciona (Apartado más técnico)

### Leer qué suena

`NowPlayingReader` habla con la app Spotify por **AppleScript**. Se eligió esto
sobre la Spotify Web API porque la Web API exige un login OAuth para una cuenta
Premium y una app registrada, mientras que AppleScript habla con la app que el
usuario ya tiene instalada y abierta. El único coste es un permiso de
Automatización, que macOS pide una vez.

```applescript
tell application "Spotify"
    set pState to (player state as text)
    set p to player position
    set t to current track
    return {pState, name of t, artist of t, album of t, p, (duration of t)/1000}
end tell
```

Tres trampas que este proyecto ya resolvió (y que hay que conocer antes de
tocar ese archivo):

1. **`st` es un token reservado** en AppleScript: `set st to …` falla con
   -2741. Por eso la variable se llama `pState`.
2. **El separador decimal es una coma**, porque el locale del sistema es
   `en_ES`: `"157,533"` no se puede convertir a `Double` y el resultado sería
   0 — la letra se congelaría sin ningún error visible.
3. **Mezclar propiedades de la app con las del track rompe la llamada**: un
   `get {name, artist, player position, …}` falla con -1728. Hay que leer
   `current track` a una variable primero.

### Cómo se evita el retardo

El retardo no venía del Apple Event, sino de **pedir demasiadas cosas en cada
lectura**. Medido en esta Mac:

| Lectura | Coste |
|---|---|
| posición + estado | ~17 ms |
| posición + estado + título | ~25 ms |
| posición + el track entero | ~50 ms |

Cada propiedad pedida es un viaje de ida y vuelta a Spotify. Así que la
lectura se partió en dos:

- **Rápida** (cada 200 ms): posición, estado y **título**. Son 25 ms.
- **Lenta** (una vez por canción): artista, álbum y duración. Son ~30 ms, pero
  solo cuando el título cambia.

El título es lo que identifica la pista, así que con eso alcanza: cuando el
título cambia, se busca el resto de los metadatos. El resultado: **la lectura
pasó de 280 ms a 25 ms**, y el poll pasó de 1 s a 200 ms.

Además, el motor de sincronía (`SyncEngine`) mide la latencia de cada lectura y
adelanta el ancla de posición para compensarla, y el Apple Event corre en una
cola propia para no robarle cuadros a la vista.

### Conseguir la letra

La letra viene de dos fuentes abiertas,
consultadas **en paralelo**:

| Fuente | Qué aporta | Cuándo falla |
|---|---|---|
| [LRCLIB](https://lrclib.net) | Letra con sincronía **por línea** | Devuelve `503` intermitente (se reintenta con backoff) |
| NetEase Cloud Music | Sincronía real **por palabra** (`yrc`) | No todas las canciones la tienen |
| **Musixmatch** (opcional) | Sincronía **por carácter** (`richsync`) | Necesita una API key propia |

### Permisos

La app pide **un solo** permiso:

| Permiso | Para qué |
|---|---|
| Automatización → Spotify | Leer la canción actual y la posición de reproducción |


### La pantalla

El panel no puede apagarse a voluntad desde una app sin privilegios: en esta
Mac `IODisplayWrangler` no tiene `IOCommandQueue` (así que el truco de
`SetPowerState` no está disponible) y `pmset displaysleepnow` necesita `sudo`.

Lo que sí se puede, y es lo que hace la app, es **no pelear con el sistema**:

| Modo | Qué pasa |
|---|---|
| Mantener | Una aserción `PreventUserIdleDisplaySleep` mantiene la pantalla encendida mientras se ve el overlay. |
| Apagar tras X min | La misma aserción, pero con timeout: caduca sola y el sistema apaga la pantalla según su propia política. |

## Estructura

```
Sources/MycSs/
├── main.swift                 punto de entrada; arma el NSApplication
├── App/
│   ├── AppDelegate.swift      menú de barra, ciclo de vida
│   ├── SettingsView.swift     panel de preferencias
│   └── SelfTest.swift         pruebas contra el sistema real
├── Lock/
│   ├── LockState.swift        detección de bloqueo/desbloqueo
│   ├── SkyLightOperator.swift elevación al lock screen (dlsym)
│   ├── LockOverlayPanel.swift la ventana: click-through, sin foco
│   └── LockOverlayController.swift  una ventana por display
├── Player/
│   ├── NowPlayingReader.swift AppleScript → Spotify
│   └── NowPlaying.swift       modelo
├── Lyrics/
│   ├── LyricsProvider.swift   LRCLIB + NetEase + Musixmatch en paralelo
│   ├── LRCLib.swift           /api/get y /api/search
│   ├── NetEase.swift          búsqueda + lyric/v1 (yrc)
│   ├── Musixmatch.swift       richsync (timing por carácter)
│   ├── LyricsParser.swift     LRC / yrc → modelo
│   ├── WordInterpolator.swift timing por palabra desde nivel línea
│   ├── LyricsModels.swift     Lyrics, LyricLine, LyricWord
│   └── HTTPCache.swift        reintentos con backoff + caché en disco
├── Sync/
│   └── SyncEngine.swift       poll + interpolación a 60 fps
├── Render/
│   ├── OverlayRootView.swift  la pantalla del lock screen
│   ├── LyricsView.swift       el karaoke
│   ├── BackgroundView.swift   MeshGradient y halos
│   ├── ArtworkPalette.swift   paleta desde la portada
│   ├── ThemeEngine.swift      transición entre temas
│   └── LyricsViewModel.swift  puente entre el actor y la vista
├── Power/
│   └── DisplayPower.swift     aserciones de energía
├── Settings/
│   ├── AppSettings.swift      modelo + persistencia
│   └── SystemFonts.swift      las 2.700 fuentes del sistema
└── Support/
    └── Log.swift              log a ~/Library/Logs/MycSs.log
```

## Notas de implementación

- **Swift 5 en modo `swiftLanguageMode(.v5)`**: el código de AppKit y los
  callbacks de C de SkyLight no pasan el chequeo estricto de concurrencia de
  Swift 6.
- **Target macOS 15**: `MeshGradient` (el fondo animado) necesita esa versión.
- **`@State` no está disponible**: las Command Line Tools no incluyen el plugin
  de macros de SwiftUI que `@State` necesita. El panel usa `@Bindable` sobre
  clases `@Observable`, que además es lo correcto: el objeto de ajustes es
  compartido, así que un cambio se ve al instante en el overlay.
- **El paquete se compila con SwiftPM, no con un `.xcodeproj`**: `build-app.sh`
  arma el bundle a mano y lo firma ad-hoc.

## Licencia y datos

Las letras vienen de terceros:

- [LRCLIB](https://lrclib.net) — letras sincronizadas, CC0.
- NetEase Cloud Music — endpoint no documentado. Se usa sólo como respaldo y
  sus resultados se validan igual que los de LRCLIB.

No se redistribuyen letras: la app las descarga y las cachea en disco, en
`~/Library/Caches/MycSs/Lyrics`.
