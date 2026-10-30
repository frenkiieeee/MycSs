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

```bash
./MycSs.app/Contents/MacOS/MycSs --preview --demo --snapshot-seq /tmp/frame 20 0.5
```

Muestra una letra de mentira sobre un reloj propio y guarda veinte PNGs medio
segundo apartados, para ver cómo se mueve el texto cuando cambia la línea.
Con `--demo` no se lee nada de Spotify ni de la red, así que sirve para
comprobar el movimiento sin depender de lo que esté sonando.

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

### El campo de la contraseña

El overlay tapa el campo real de la pantalla de bloqueo, así que la app
dibuja **su propio campo** en la esquina inferior izquierda, en línea con la
portada, el título y el artista. Mientras el usuario escribe, ese campo muestra
**los puntos de lo que se está escribiendo** y un **ojo** a la derecha para
descubrir el texto.

Lo que el usuario escribe **no se puede leer del campo real**: vive en otro
proceso (`loginwindow`) y un campo seguro no se deja leer ni con el permiso de
Accesibilidad. Así que la app reconstruye el texto con **el estado del
teclado**, que el sistema deja leer sin ningún permiso: se consultan las teclas
que están pulsadas y las que no lo estaban hace un instante son las que se
acabaron de pulsar. Un *event tap* pasivo también se crea sin permisos, pero en
macOS reciente el sistema no le entrega las teclas del teclado.

Con esto la app ve **qué teclas** se pulsan (y el borrado), nunca otra cosa.

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

### Cómo aparece

El overlay no salta de golpe sobre la pantalla de bloqueo. Hay tres entradas
configurables: **fundido**, **caer desde arriba** y **subir desde abajo**.

Mientras las letras se están descargando, la **portada aparece sola en el centro**
de la pantalla; cuando llegan, la portada se desplaza a la izquierda con un
movimiento suave y las letras aparecen al lado. La pantalla nunca queda vacía.

Para que las letras estén listas al bloquear, la app **escucha Spotify todo el
tiempo**, también con la Mac desbloqueada: no dibuja nada, pero ya sabe qué
canción suena y tiene la letra en camino. Por eso al bloquear aparecen casi
inmediatamente.

### El resaltado

Hay tres formas de marcar la letra, a elección del usuario:

| Modo | Qué hace |
|---|---|
| Línea completa | Marca la línea entera que se está cantando, sin seguir la palabra. |
| Palabra a palabra | La línea se va iluminando progresivamente, siguiendo la letra. |
| Palabra destacada | Además, la palabra activa se agranda y las vecinas se atenúan. |

El reparto del tiempo entre palabras se puede ajustar: **proporcional a la letra**
(cada palabra recibe el tiempo que le corresponde por su tamaño, y las pausas quedan
vacías — la letra termina de iluminarse cuando termina de cantarse) o **proporcional
al espacio** (las palabras se reparten uniformemente).

### Cómo se mueve la letra

La letra es una columna alta que se desliza: la línea que se está cantando se queda
en el medio de la pantalla y el resto va pasando por debajo. El movimiento es una
**traslación**, nunca un fundido ni un desenfoque, para que el ojo pueda seguir el
texto.

El desplazamiento lo hace la propia app, con un `offset`, y no el `ScrollView` de
SwiftUI: en este sistema `scrollPosition` y `scrollTo` no mueven nada —el desplazamiento
del scroll view se queda donde estaba—, así que la distancia se calcula a mano con la
altura de cada línea, que se mide al maquetar.

Dos detalles hacen que el movimiento no dé un tirón:

- **Todas las líneas están siempre en la columna.** Dibujar solo una ventana alrededor
  de la línea activa insertaría y quitaría vistas mientras suena la canción, y cada
  inserción mueve el texto que está debajo.
- **Una línea mide lo mismo esté activa o no.** La línea activa se dibuja con el
  relleno del karaoke y las demás sin, pero las dos son el mismo `Text` con la misma
  fuente, así que miden igual y una línea no cambia de alto cuando le toca.

- **La línea activa se dibuja sola.** La columna de letras no lee la posición de
  la canción: solo la línea que se está cantando lo hace. Así, mientras suena la
  música solo se redibuja esa línea y la columna —setenta líneas— no se vuelve a
  medir en cada fotograma.

- **El halo es una sombra, no una copia difuminada.** Una copia de la línea
  difuminada se corta en el borde de la vista, y ese corte se ve como una pared
  invisible alrededor del texto. Una sombra la dibuja el sistema de gráficos
  alrededor de las letras, sin recortarse.

- **El relleno del karaoke es por palabra, no por carácter.** El relleno avanza
  dentro de la palabra que se está cantando, y la palabra entera se enciende de
  golpe al terminarse. Un relleno por carácter avanza a saltos de un carácter, y
  a ese tamaño se nota.

### La tipografía

La app usa la tipografía de Apple: **SF Pro**, la fuente del sistema. No se puede
pedir por nombre —CoreText se niega a devolver las fuentes del sistema y devuelve
Times en su lugar— así que se resuelve con `NSFont.systemFont`, que es la única vía
correcta. El selector de fuentes ofrece las ~2.700 fuentes instaladas para quien
prefiera otra cosa.

### El color

El tema sale de la **portada**: se descartan los píxeles casi blancos o sin color, se
agrupan los que quedan y se eligen el acento, el color secundario y los dos tonos
del fondo. Si la portada es monocroma, la app cae al tema por defecto en vez de
inventar un color.

Los halos del fondo llevan el color de la portada, no blanco: sobre un fondo negro,
unos halos blancos se leen como un resplandor de la pantalla y no como el color del
álbum.

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
│   ├── LyricsProvider.swift   LRCLIB + NetEase en paralelo, validación
│   ├── LRCLib.swift           /api/get y /api/search
│   ├── NetEase.swift          búsqueda + lyric/v1 (yrc)
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
- **Los `scrollPosition` y `scrollTo` de SwiftUI no funcionan aquí**: el
  desplazamiento del scroll view no se mueve. La columna de la letra se mueve
  con un `offset` calculado a partir de la altura de cada línea. La animación va
  con `.animation(_:value:)` sobre la línea activa, y no con `withAnimation`:
  el overlay se reconstruye sesenta veces por segundo, y la actualización que
  lee el valor nuevo no es la que lleva la animación.
- **Una vista nueva reinicia el estado compartido**: el estado de la entrada
  (el fundido de aparición) es un objeto compartido, así que una segunda copia
  del overlay —la que dibuja la captura— reiniciaba el fundido del overlay que
  estaba en pantalla.

## Licencia y datos

Las letras vienen de terceros:

- [LRCLIB](https://lrclib.net) — letras sincronizadas, CC0.
- NetEase Cloud Music — endpoint no documentado. Se usa sólo como respaldo y
  sus resultados se validan igual que los de LRCLIB.

No se redistribuyen letras: la app las descarga y las cachea en disco, en
`~/Library/Caches/MycSs/Lyrics`.
