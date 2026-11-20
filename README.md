<div align="center">

<img src="Assets/Mascot/png/mycss-feliz-512.png" width="140" alt="La mascota de MycSs">

# MycSs

**Una capa creativa para tu Mac.** Letras sincronizadas palabra a palabra sobre la pantalla de bloqueo, y un notch que reúne música, calendario y más.

![Versión](https://img.shields.io/badge/versi%C3%B3n-0.2.5-FFD400?style=flat-square)
![macOS](https://img.shields.io/badge/macOS-15%2B-0B0B0F?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5-F05138?style=flat-square)
![Licencia](https://img.shields.io/badge/licencia-MIT-3A3A46?style=flat-square)

[Instalación](#instalación) · [Funciones](#qué-hace) · [Permisos](#permisos) · [Solución de problemas](#solución-de-problemas) · [English](README.en.md)

</div>

---

## Qué hace

**Letras en la pantalla de bloqueo.** Al bloquear la Mac aparece la letra de la canción que suena en Spotify o Apple Music, resaltada **palabra a palabra** al ritmo de la voz, con la portada, un reloj y un fondo animado que toma los colores del álbum. También se abre como salvapantallas con un atajo (por defecto ⌃⌥L), desde el menú de la barra o tras un rato sin usar la Mac.

**Un notch con música y widgets.** El notch muestra la portada y un visualizador mientras suena algo, el título al cambiar de canción, el volumen, el brillo y la luz del teclado (con un atajo propio, ⌥F2 y ⌥F1, que puedes cambiar), las notificaciones, y se abre con el puntero hasta un panel con el reproductor y widgets: calendario, recordatorios, temporizador, batería y sistema, portapapeles y una estantería para archivos. También sale en otras pantallas.

**Tuyo hasta el último detalle.** Fuente y efecto de resaltado, reloj (que puede ocultarse solo), fondos, animaciones de entrada y de cambio de canción, tamaño y movimiento del notch, indicadores de volumen... Todo se guarda como **estilos** (de fábrica o propios) que se pueden ver en una vista previa antes de aplicarlos.

### Funciones

| Área | Qué incluye |
|---|---|
| Letras | Palabra a palabra (LRCLIB, NetEase y QQ Music), tema desde la portada, fondo animado, profundidad como Apple Music, cambio de canción animado con o sin letra |
| Reproductores | Spotify y Apple Music, sin APIs privadas (AppleScript). Controles de reproducción bajo la portada |
| Pantalla | Reloj configurable con ocultación automática, marca de agua `@frenkiieeee` discreta, Esc o clic fuera para salir |
| Notch | Música, volumen, brillo y luz del teclado (barra, deslizador, anillo, segmentos), notificaciones, estantería, varias pantallas, animación de canción nueva configurable |
| Widgets | Calendario (crea eventos y recordatorios pulsando la fecha), recordatorios, temporizador, sistema, portapapeles |
| Ajustes | Vistas previas en vivo, estilos propios, restaurar valores con «Deshacer», abrir al iniciar sesión, buscar actualizaciones |

## Requisitos

- macOS 15 (Sequoia) o superior.
- Spotify o Apple Music, con una sesión iniciada.
- Un Mac con notch para el notch completo. En los demás se dibuja una píldora arriba al centro.

## Instalación

### Homebrew

```bash
brew install --cask frenkiieeee/mycss/mycss
```

### Un comando

```bash
curl -fsSL https://raw.githubusercontent.com/frenkiieeee/MycSs/main/install.sh | bash
```

Descarga la última versión, comprueba su suma sha256, la copia a `/Applications` y la abre. Opciones: `--version X.Y.Z`, `--prefix DIR`, `--from-source`. Léelo antes de ejecutarlo si prefieres: es corto.

### Desde el DMG

1. Descarga `MycSs-<versión>.dmg` de la página de [Releases](https://github.com/frenkiieeee/MycSs/releases).
2. Arrastra **MycSs** a Aplicaciones.
3. La primera vez, **clic derecho > Abrir > Abrir**: la app no está notarizada por Apple, y por eso macOS avisa. Si dice que está dañada, ejecuta `xattr -dr com.apple.quarantine /Applications/MycSs.app`.

### Desde el código

Hacen falta solo las Command Line Tools de Xcode (`xcode-select --install`), no Xcode.

```bash
git clone https://github.com/frenkiieeee/MycSs.git
cd MycSs
./build-app.sh        # compila y arma MycSs.app
open MycSs.app
```

### Actualizar y desinstalar

- Actualizar: `brew upgrade --cask mycss`, o vuelve a ejecutar `install.sh`, o usa «Buscar actualizaciones» en Preferencias > Acerca de. **Tras actualizar, macOS puede pedir de nuevo** Accesibilidad y Acceso total al disco (la app no está notarizada y su firma cambia).
- Desinstalar: `brew uninstall --cask --zap mycss`, o `./scripts/uninstall.sh`. Quita la app, sus preferencias, la caché y los registros.

## Primeros pasos

1. Abre MycSs: aparece su icono en la barra de menús (y el notch, si tienes la música sonando).
2. Pon una canción en Spotify o Apple Music. macOS pedirá permiso de **Automatización** la primera vez.
3. Bloquea la Mac (⌃⌘Q) o pulsa **⌃⌥L** para ver las letras sin bloquear.
4. Abre **Preferencias** desde el menú de la barra: estilos, letras, reloj, apariencia y notch, con vistas previas en vivo.
5. Opcional: activa «Abrir MycSs al iniciar sesión» en General.

## Permisos

MycSs pide cada permiso **solo cuando lo necesita** y funciona sin los opcionales.

| Permiso | Para qué | Cuándo se pide |
|---|---|---|
| Automatización (Spotify, Música) | Leer la canción y la posición | Al reproducir por primera vez. **Imprescindible** |
| Accesibilidad | Teclas de volumen y brillo en el notch, y el atajo de la luz del teclado | Al activar el indicador del notch. Opcional |
| Acceso total al disco | Ver las notificaciones de otras apps en el notch | Si lo activas en Notch > Widgets (Notificaciones). Opcional |
| Calendarios | Eventos del widget de calendario | Al abrir ese widget. Opcional |
| Recordatorios | Widget de recordatorios | Al abrir ese widget. Opcional |
| Audio del sistema | Visualizador que sigue el ritmo real | Si activas «seguir el ritmo». Opcional |

## Privacidad

Todo ocurre en tu Mac. Lo único que sale es:

- La **búsqueda de la letra**: título, artista y duración de la canción a [LRCLIB](https://lrclib.net), NetEase Cloud Music y QQ Music. Las letras se guardan en `~/Library/Caches/MycSs`; no se redistribuyen.
- La comprobación de versión, **solo si pulsas** «Buscar actualizaciones» (una consulta a la API pública de GitHub, sin datos tuyos).

No hay análisis de uso, cuentas ni conexiones en segundo plano. Los eventos, recordatorios y notificaciones se leen en local y no se envían a ningún sitio.

## Solución de problemas

- **No aparece la letra al bloquear.** Mira el registro: `tail -f ~/Library/Logs/MycSs.log` (o Preferencias > Acerca de > Abrir el registro). Comprueba que la canción suena y que concediste Automatización.
- **Una canción no tiene letra.** Algunas no están en ninguna fuente; MycSs reintenta y centra la portada. El banco de pruebas (`MycSs --lyrics-bench`) mide cuántas canciones conocidas encuentra.
- **Se perdieron Accesibilidad o Acceso total al disco tras actualizar.** Es normal sin notarización: vuelve a concederlos en Ajustes del Sistema > Privacidad y seguridad. Para Acceso total al disco, MycSs no aparece solo en la lista: añádelo con «+».
- **El notch no se ve en una pantalla.** Notch > «Pantallas» elige solo la del Mac o todas.
- **No arranca / se cierra.** Mira `~/Library/Logs/DiagnosticReports` y abre una incidencia con el registro.

## Para quien quiera ver o tocar el código

- [`docs/README.md`](docs/README.md): índice de la documentación (specs, decisiones, marca).
- [`docs/architecture/internals.md`](docs/architecture/internals.md): cómo funciona por dentro (lectura de la música, retardo, notch, permisos, trampas).
- [`CONTRIBUTING.md`](CONTRIBUTING.md): cómo compilar, probar y qué reglas seguir.
- [`CHANGELOG.md`](CHANGELOG.md) y [`docs/RELEASING.md`](docs/RELEASING.md): versiones y cómo se publica una.

```bash
./scripts/verify.sh           # compila, autoprueba y comprueba los enlaces de la documentación
./scripts/verify.sh --notch   # además abre el notch real y pulsa sus controles
```

## Hoja de ruta

- Notarización con Developer ID (sin avisos al abrir ni permisos perdidos al actualizar).
- Capturas y GIFs de la app en este README.
- Más widgets y más fuentes de letras.

## Licencia y créditos

[MIT](LICENSE) © 2026 Frenkiieeee.

- El notch se inspira en [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0). **No se copió código suyo**; solo la idea de producto.
- Letras de [LRCLIB](https://lrclib.net) (CC0), NetEase Cloud Music y QQ Music (endpoints no documentados; si dejan de responder, la app sigue con LRCLIB). Las letras pertenecen a sus autores.
- Mascota y marca: Frenkiieeee (ver [`docs/brand/frenkiieeee.md`](docs/brand/frenkiieeee.md)). Tipografía Nunito, licencia OFL.
