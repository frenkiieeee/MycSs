# Arquitectura actual

SwiftPM, un solo target ejecutable `MycSs` (`Sources/MycSs`), app de agente sin icono en el Dock. El detalle técnico y las trampas ya resueltas están en el [README](../../README.md); aquí solo el mapa.

| Módulo | Responsabilidad |
|---|---|
| `App/` | Menú de barra, ciclo de vida, ajustes, autotest |
| `Lock/` | Detectar bloqueo, elevar la ventana al Space del lock screen (SkyLight), un panel por pantalla |
| `Player/` | Qué suena. `PlayerSource` es el protocolo; `SpotifySource` lo implementa con AppleScript |
| `Lyrics/` | Letras desde LRCLIB y NetEase en paralelo, parsers, tiempo por palabra, caché en disco |
| `Sync/` | `SyncEngine` (actor): sondeo cada 200 ms e interpolación de la posición a 60 fps |
| `Render/` | Vistas SwiftUI del overlay, fondo animado, paleta desde la portada |
| `Settings/` | `AppSettings` en `UserDefaults`, fuentes del sistema |
| `Power/` | Aserciones para mantener o apagar la pantalla |

## Acoplamientos conocidos (lo que las fases siguientes tienen que abrir)

- `OverlayRootView` tiene el layout fijo (reloj arriba, portada izquierda, letras derecha). La Fase 3 lo reemplaza por un tema serializable.
- `LockOverlayController` solo sabe presentarse como lock screen. La Fase 1 separa qué se dibuja de cuándo y cómo se presenta.
- `AppSettings` son claves sueltas. La Fase 3 las migra a un modelo `Codable`.
