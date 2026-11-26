# 014 El navegador como reproductor

Estado: hecho (los scripts de la página, probados en JavaScriptCore con una página simulada; Zen, con su sesión real y un estado del sistema inyectado; sin probar con audio real en Zen, Chrome o Safari)

## Objetivo
Ver y controlar en MycSs lo que suena en una pestaña del navegador (YouTube, SoundCloud, Spotify web...), con el favicon de la pestaña como portada, y pasar con un clic entre el navegador, Spotify y Apple Music.

## No objetivos
Pestañas en modo incógnito si el navegador no las deja leer. Letras para vídeos que no son canciones.

## Datos
- `BrowserSource` (otro `PlayerSource`, ver [ADR 007](../decisions/007-navegador-con-applescript.md)): Safari (`do JavaScript`) y la familia Chromium (Chrome, Brave, Edge, Arc, Vivaldi, Chromium) con `execute javascript`. Solo se habla con los navegadores abiertos.
- **Firefox, Zen, Floorp, LibreWolf y Waterfox** no se pueden scriptar: se leen del Now Playing del sistema con una librería propia que carga `perl` ([ADR 008](../decisions/008-now-playing-con-perl.md)): título, artista, posición y botones. El favicon sale de su archivo de sesión (`recovery.jsonlz4`, con el título y el icono de cada pestaña); si la pestaña es demasiado nueva, el icono del propio navegador. No piden ningún ajuste en el navegador.
- Un script pequeño en la página lee el `<video>` o `<audio>` que suena (estado, posición, duración), `navigator.mediaSession.metadata` (título, artista, álbum) y el mejor icono de la página (`apple-touch-icon` antes que el favicon).
- Barrido de todas las pestañas como mucho cada 4 s mientras no hay ninguna sonando; con una pestaña encontrada, solo se lee esa.
- Portada: el icono, descargado sin cookies, sobre un fondo de su propio color. Solo en memoria (no se guarda en disco ni se busca en catálogos de música).
- Órdenes (Firefox y derivados: las del sistema, que llegan a la app que suena; saltar a una posición solo si la página lo admite): reproducir y pausar, saltar a una posición; siguiente y anterior con los botones de la página cuando los hay (YouTube, SoundCloud, Spotify web) y, si no, volver al principio.

## Interfaz
- General, Reproductor: «Seguir a» suma **Navegador**; interruptor «Incluir el navegador en «Automático»» (encendido por defecto; elegir «Navegador» lo lee aunque esté apagado) y el estado de cada navegador abierto, con lo que falta.
- Notch abierto: una pastilla con el reproductor actual (Spotify, Música o el sitio); un clic pasa al siguiente que tenga algo. También en el menú de la barra («Cambiar de reproductor»).

## Permisos y riesgos
Automatización para cada navegador y, en cada uno, activar «Permitir JavaScript desde eventos de Apple» (Chrome: Ver › Opciones para desarrolladores; Safari: Desarrollo, con las funciones para desarrolladores activas). El script solo lee el reproductor de la página y no envía nada.

## Verificación
`--selftest-pure`: el formato de la sesión de Firefox (mozlz4), encontrar la pestaña por su título, iconos `data:` y SVG, las líneas de la librería. `--selftest`: la librería dentro de `perl` y, con Zen abierto, su archivo de sesión real y la lectura completa con una pestaña real. Interpretar las respuestas del script (sonando, en pausa, vacío, roto) y el orden del cambio de reproductor. A mano: un vídeo de YouTube en Chrome con el permiso activado.
