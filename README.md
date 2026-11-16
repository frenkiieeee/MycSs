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

La letra viene de tres fuentes abiertas o públicas:

| Fuente | Qué aporta | Cuándo falla |
|---|---|---|
| [LRCLIB](https://lrclib.net) | Letra con sincronía **por línea**. Cubre casi todo | Devuelve `503` intermitente (se reintenta con backoff) |
| NetEase Cloud Music | Sincronía real **por palabra** (`yrc`) | No todas las canciones la tienen |
| QQ Music | Sincronía por línea. **Solo respaldo**: se consulta si las otras dos no encuentran nada | Endpoint no documentado |

LRCLIB y NetEase se consultan **a la vez**. La primera letra que pasa la
validación se muestra enseguida; si después llega una con tiempo por palabra
y la primera no lo tenía, la sustituye. QQ Music solo se pregunta cuando las otras
dos terminan sin resultado, o a los 2,5 s si todavía no ha llegado nada. Si ninguna
tiene la letra, la portada pasa al centro con una animación, y a los 8 s se
vuelve a intentar una vez (las fuentes fallan por rachas).

Medido con `MycSs --lyrics-bench --hard` (67 canciones, entre ellas latinas,
asiáticas, antiguas e indie): **66 de 67** (la que falta es un instrumental, que
no tiene letra) y **27 con tiempo por palabra**. `--providers` muestra qué cubre cada
fuente por separado.

Dos trampas que este proyecto ya resolvió:

1. **NetEase y las cookies.** En su primera respuesta NetEase pone una cookie
   (`NMTID`); con ella, las búsquedas siguientes devuelven canciones sin relación
   (una balada china para «Shape of You»). Con la cookie puesta, solo acertaba la
   primera consulta de cada sesión y el tiempo por palabra casi nunca llegaba. El
   cliente HTTP (`HTTPCache`) **no guarda cookies**, a propósito. Ninguna fuente
   las necesita.
2. **Los títulos decorados.** Spotify y Music mandan «- Remastered 2011» y
   «(feat. X)», y varios artistas en un solo texto. Las búsquedas se hacen también
   con el título limpio y el primer artista.

### El reproductor

Debajo de la portada hay anterior, play y pausa, siguiente y una barra con el
tiempo y la duración. Las órdenes van por AppleScript igual que la lectura
(`playpause`, `next track`, `previous track`, `set player position to`) y el motor
adelanta la posición al instante, sin esperar al siguiente sondeo. «Anterior»
reinicia la canción si ya van más de 3 s.

En la pantalla de bloqueo la ventana deja pasar los clics, así que los botones no
son `Button` de SwiftUI: cada uno informa de dónde está en pantalla
(`screenRegion`) y el modelo comprueba contra esas zonas cada clic que detecta. Es
el mismo camino en el salvapantallas, para tener un solo comportamiento que acertar.

### El notch

Apagado por defecto (Preferencias, Notch). Cerrado, con música sonando se
ensancha a cada lado: la **portada del álbum** a la izquierda y un visualizador de
cinco palitos finos, del color del álbum, a la derecha (solo por fuera: abierto no
sale). **Sin música se pliega** hasta ser exactamente el notch del hardware, unos
segundos después de una pausa para que no parpadee (se puede desactivar). Al cambiar de canción se ensancha unos segundos más
con el título y el artista (el «vistazo»).

**Abierto** (al pasar el ratón o al pulsarlo; 640 × 176 pt de diseño y, por defecto, al 86 %: el tamaño es un ajuste, del 70 al 130 %)
tiene dos pestañas en la franja de arriba, a los lados del hueco, y un botón de
ajustes:

- **Inicio**: la música ocupa el **60 %** de la izquierda (portada con el icono del
  reproductor, progreso, botones) y a la derecha, el **40 %**, un widget a elegir:
  calendario, recordatorios, temporizador, batería y sistema o portapapeles (iconos en
  su esquina; se activan en Preferencias › Notch). El calendario: la semana con hoy en el centro,
  el día seleccionado en amarillo y sus eventos (color de su calendario y horas).
  **Dos dedos a los lados sobre el calendario** recorren los días, con un tic del
  trackpad por cada uno (hasta 14 días atrás y 45 adelante); un toque sobre un día lo
  elige. La tira desliza bajo una ventana de siete días y el día elegido queda
  siempre en el centro.
  El calendario se lee con EventKit y el permiso se pide la primera vez; en el
  binario de `swift build`, que no tiene `Info.plist`, queda desactivado porque
  EventKit cerraría la app.
  **Pulsar la fecha** del calendario (mes y año, con un «+») abre una ventana pequeña bajo
  el notch para crear un **evento** o un **recordatorio** en ese día: título, hora, duración
  o todo el día; Intro crea y Esc cancela (spec 009). Se guarda en el calendario y la lista
  por defecto de la Mac.
  Los **recordatorios** se tachan con un clic; el **temporizador** (5, 10, 25, 45 min)
  sigue corriendo con el notch cerrado y ensancha su lado derecho con la cuenta atrás;
  **batería y sistema** muestra batería, CPU y memoria; el **portapapeles** guarda lo
  último que copias (apagado por defecto, ocho entradas, solo en memoria) y un clic
  lo vuelve a copiar.
- **Bandeja**: un sitio para dejar archivos. Se sueltan en el notch, se arrastran
  fuera cuando hacen falta o se mandan por AirDrop. Arrastrar un archivo hacia el
  notch abre la bandeja. Solo se guardan las rutas, nunca copias.

**Notificaciones.** `NotificationsModel` lee (solo lectura) la base donde macOS guarda
las notificaciones y enseña la nueva unos segundos: el notch cerrado se ensancha con el
icono de la app y, abierto, la cabecera la muestra. Exige **Acceso total al disco**
(Preferencias › Notch muestra si está concedido) y **no puede ocultar el aviso del
sistema**: para verlo solo en el notch hay que poner el estilo de aviso en «Ninguno»
en Ajustes del Sistema › Notificaciones. Probado con una base sintética con el mismo
esquema (`--notification-selftest`); con la real, sin el permiso, el estado es
«denegado» y no se ha podido probar aquí.

**Movimiento y aspecto.** Preferencias › Notch elige el movimiento (suave, elástica,
rápida, lenta), cómo se abre (a la vez, o primero a los lados y luego hacia abajo),
cómo se muestra una canción nueva (hacia los lados o hacia abajo), el visualizador
(barras, onda, puntos), el indicador de volumen y brillo (barra, número, anillo), el
color de acento, la portada (cuadrada o disco que gira) y tres estilos que lo cambian
todo de golpe, con «Deshacer». Con el notch abierto, al subir o bajar el volumen o el
brillo el valor sale en su cabecera. Para la canción nueva «Hacia los lados» se elige cuánto se ensancha, cuánto dura la animación y cuánto tiempo queda abierto.

**Vista previa.** Estilos, Letras, Reloj, Apariencia y Notch tienen arriba una vista
previa en vivo con una canción de muestra (`SettingsPreview.swift`): el overlay entero
o el notch real, con botones para ver cerrado, canción nueva, abierto, volumen, brillo,
aviso y temporizador. `MycSs --demo --settings-snapshot /tmp/sp` las guarda como PNG.

**Indicador de volumen y brillo.** El valor viaja de uno a otro con un muelle (no salta):
la barra, el deslizador, el anillo, los segmentos y el número. Se elige el indicador, el
número (cuenta paso a paso, dígitos que ruedan, fijo u oculto), el movimiento (suave,
elástico, deslizante) y la entrada (crece desde el notch, rebote, desliza, fundido). El
valor que se dibuja es `NotchModel.hudShown`, que se anima hacia el real; el indicador
aparece donde estaba el valor y viaja hasta el nuevo. Con el notch abierto sale en la
cabecera con el mismo estilo.

**Los ajustes se ven en el notch en marcha.** El notch de la ventana real recibe el contador
`SettingsRevision` (`NotchRoot`), así que cambiar un ajuste lo redibuja sin reiniciar.

**Ver un estilo sin aplicarlo.** Tocar un estilo lo dibuja en la vista previa con sus valores
en una capa temporal (`SettingsOverride`) que solo existe mientras se dibuja una imagen
(unas cuatro veces por segundo); «Aplicar» lo deja puesto y «Volver a lo mío» lo quita.

**Tamaño cerrado.** Preferencias › Notch: «Tamaño del notch cerrado» (50 a 130 %, por
defecto 72 %) ajusta el ancho de los lados y lo que llevan (portada, visualizador,
título, indicador). El alto es el del hueco de la pantalla y no puede ser menor.

**Estilos propios.** Estilos (letras) y Notch tienen la lista de estilos hechos y los
tuyos: «Guardar los ajustes actuales» crea uno con el nombre que escribas, con lápiz
se renombra o se actualiza con los ajustes de ahora y con la papelera se borra. El
estilo aplicado lleva la etiqueta **EN USO**, o **MODIFICADO** si cambias algo después.
Se guardan en `UserDefaults` (`customStyles`) como una foto de los ajustes de su tipo
(`StyleDomain.keys`).

**Icono de la barra de menú.** «Ocultar el icono mientras el notch está activo»: con
el notch apagado el icono vuelve siempre; el engranaje del notch y volver a abrir la
app abren las preferencias.

**Cómo está hecho** (`Sources/MycSs/Notch/`). La ventana (`NotchPanel`) tiene un
tamaño fijo, transparente, y **no se toca nunca `ignoresMouseEvents`**: macOS deja
pasar los clics por los píxeles transparentes de una ventana sin borde, y los coge
donde hay dibujo. Así el notch recibe hover y clics de verdad, sus botones son
`Button` normales, y la barra de menús que queda debajo sigue funcionando. Una
sola forma negra (`NotchShape`) cambia de tamaño con un único muelle; el contenido
se coloca ya a su tamaño final y la forma lo va descubriendo, con
`blurReplace` entre estados y la portada viajando del notch cerrado al abierto
(`matchedGeometryEffect`). Un único `NotchModel` decide el estado (abrir, cerrar,
vistazo, indicador) y un `NotchController` lo alimenta desde fuera.

**Fijo entre escritorios.** La ventana del notch vive en un Space propio, siempre
visible y del nivel más alto (`SkyLight.pinToAllDesktops`), no en un escritorio.
Así, al moverte entre escritorios o apps a pantalla completa, el notch no se desliza
con ellos. Es la estructura que usa boring.notch. Ese Space se oculta del código del
bloqueo, que de otro modo lo tomaría por el de la pantalla de bloqueo.

**Volumen y brillo, un solo indicador.** Para mostrarlos en el notch, MycSs se queda
con las teclas (`MediaKeyTap`, un CGEventTap en el `cghidEventTap`), y eso exige el
permiso de **Accesibilidad**. Con el permiso solo sale el del notch; **sin él, solo
sale el del sistema**: el notch no dibuja el suyo, para que nunca aparezcan los dos.
(`VolumeWatcher`, que escucha el dispositivo de salida, solo muestra el volumen
cuando las teclas están tomadas: así recoge los cambios que no vienen de las teclas,
como el control deslizante del Centro de control, que no tienen indicador del
sistema.) Una tecla solo se toma si el cambio se hizo de verdad: si la salida de
audio no tiene volumen (HDMI) o la pantalla no tiene brillo, la tecla va al sistema.

**Firma estable.** macOS liga el permiso de Accesibilidad a la firma de la app. La
firma «ad-hoc» tiene como requisito el hash exacto del binario, que cambia en cada
compilación, así que había que volver a conceder el permiso tras cada una.
`./scripts/make-dev-cert.sh` crea (una vez) una identidad autofirmada en un llavero
propio dentro del proyecto, `.dev-signing/` (no está en git, no toca tu llavero de
inicio de sesión ni la lista de llaveros), y `./build-app.sh` la usa sola. Con ella
el requisito pasa a ser `identifier "com.mycss.lyrics" and certificate leaf = H"…"`,
que no cambia entre compilaciones. Tras la primera compilación firmada hay que
conceder los permisos (Accesibilidad, Calendarios, Automatización) una vez más.

**Visualizador con el ritmo real** (opcional): un *tap* de Core Audio copia lo que
suena, antes de llegar a los altavoces, y lo reduce a cinco bandas (graves a
agudos) con filtros sencillos. No graba ni guarda nada. Pide el permiso de
grabación de audio del sistema la primera vez. Solo funciona mientras suena música;
si falla, el notch vuelve a la animación simulada.

**Pruebas.** `MycSs --demo --notch-selftest /tmp/n` abre la ventana real del notch,
la recorre por todos sus estados y **pulsa sus controles con eventos de ratón
reales** (play y pausa, siguiente, anterior, la barra de progreso, un día del
calendario, las pestañas, el hover), y guarda fotogramas de cada paso, también en
mitad de la animación. Con `--demo` las órdenes van a un reproductor de mentira y
nunca tocan lo que estés escuchando.

### Estilos y personalización

**El reloj se va solo.** Con las letras abiertas (pantalla de bloqueo o salvapantallas)
el reloj se quita a los 3 segundos, con un fundido, y lo demás sube a su sitio. Se
configura en Reloj: activarlo, los segundos (1 a 30) y si vuelve al mover el ratón. En
la vista previa, «Repetir» lo enseña. **La firma** `@frenkiieeee` va pequeña abajo a la
izquierda; ya no hay logo junto al título.


En Preferencias, **Estilos** aplica de golpe un aspecto (Music, Frenkiieeee,
Clásico, Minimal); **Reloj** controla tamaño, familia, grosor, color y alineación; y
Apariencia ofrece, entre otros fondos, la **portada difuminada** y poner la portada
a la derecha. Las líneas de la letra lejanas a la activa se reducen y se desenfocan
un poco (se puede apagar en Letras).

### Salir de las letras

**Esc** o un **clic fuera de las letras** cierran el overlay. En el salvapantallas
lo cierran; en el bloqueo lo ocultan hasta el siguiente bloqueo, para ver la pantalla
de bloqueo normal. Si el salvapantallas se abrió solo por inactividad, lo cierra
cualquier tecla o movimiento del ratón. Límite: la pantalla de bloqueo puede ocultar
qué teclas se pulsan mientras se escribe la contraseña; entonces Esc no se detecta y
queda el clic.

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

Un solo permiso es imprescindible (Automatización); el resto, solo si activas la función:

| Permiso | Para qué |
|---|---|
| Automatización → Spotify y Music | Leer la canción actual y la posición de reproducción |
| Calendarios (acceso completo) | Solo si se activa el calendario del notch y se abre Inicio |
| Recordatorios (acceso completo) | Solo con el widget de recordatorios |
| Acceso total al disco | Solo con «notificaciones en el notch»: para leer su base de datos |
| Accesibilidad | Solo con «volumen y brillo en el notch»: para quedarse con esas teclas |
| Grabación de audio del sistema | Solo con «visualizador con el ritmo real» |


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

**Al cambiar de canción** (Apariencia › Cambio de canción: sin animación, fundido, deslizar
o cinematográfica, con duración propia) la letra vieja sale hacia arriba y se queda congelada
hasta terminar de salir, la portada nueva entra sobre la anterior con un zoom suave, el título
y el artista cambian con un desplazamiento corto, y la letra nueva entra desde abajo cuando
llega. Si la canción nueva no tiene letra, la portada pasa al centro sin corte, y si la
anterior no la tenía, la letra entra al llegar. En la vista previa, el botón «Cambiar canción»
y el selector «Con letra / Sin letra» enseñan cada caso (spec 008).

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
│   ├── PlayerSource.swift     protocolo: lectura, portada y órdenes
│   ├── SpotifySource.swift    AppleScript → Spotify
│   ├── AppleMusicSource.swift AppleScript → Music
│   ├── PlayerHub.swift        elige el reproductor que suena
│   └── NowPlaying.swift       modelo
├── Lyrics/
│   ├── LyricsProvider.swift   LRCLIB + NetEase en paralelo, QQ de respaldo, mejora progresiva
│   ├── QQMusic.swift          búsqueda + fcg_query_lyric_new
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
- NetEase Cloud Music y QQ Music: endpoints no documentados. Se usan como
  complemento y respaldo, y sus resultados se validan igual que los de LRCLIB
  (título, artista y duración). Si dejan de responder, la app sigue con LRCLIB.

No se redistribuyen letras: la app las descarga y las cachea en disco, en
`~/Library/Caches/MycSs/Lyrics`.
