# 008 Firefox y Zen, desde el Now Playing del sistema con una librería en perl

**Decisión:** leer y controlar lo que suena en Firefox, Zen y derivados (Floorp, LibreWolf, Waterfox) desde el «Now Playing» del sistema, con una librería propia (`Support/NowPlayingAdapter/adapter.m`) que carga `/usr/bin/perl` y que habla con MediaRemote desde dentro.

**Por qué:** estos navegadores no tienen AppleScript para pestañas ni para ejecutar JavaScript, así que [007](007-navegador-con-applescript.md) no les vale. Sí publican lo que suena al Now Playing, como cualquier app de medios. MediaRemote está cerrado a terceros desde macOS 15.4 ([001](001-applescript-no-mediaremote.md)), pero no a los binarios del sistema: `perl` conserva el permiso y carga una librería cualquiera con `DynaLoader`. Es la alternativa de reserva que ya anotaba la 001 (la usa también boring.notch, sin copiar su código: la librería es de MycSs).

**Cómo:** la librería imprime una línea JSON cada 300 ms (app que suena, estado, título, artista, posición) y acepta órdenes por su entrada. Se arranca solo si hay un navegador de la familia abierto y la lectura del navegador está activada, y termina sola cuando MycSs cierra la tubería. El favicon sale del archivo de sesión del navegador (`sessionstore-backups/recovery.jsonlz4`), que lista cada pestaña con su título y su icono: se busca la pestaña por el título que suena.

**Coste y riesgos:** depende de que Apple no le quite a `perl` ese permiso (lo anotado en la 001). Si pasa, la librería avisa y Firefox y Zen dejan de leerse, sin tocar el resto. No hay permiso nuevo de macOS. Se compila en `build-app.sh` con las Command Line Tools y va dentro del `.app`, así que quien instala el DMG no necesita nada. Las órdenes llegan a la app que el sistema considera «la que suena», no a una pestaña concreta; siguiente, anterior y saltar solo funcionan si la página los ofrece.

**Revertir:** quitar `SystemNowPlaying`, `FirefoxSession` y `Support/NowPlayingAdapter`; el resto de navegadores no depende de ello.
