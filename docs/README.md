# Docs de MycSs

Estos documentos son la memoria del proyecto: lo que una persona o un agente necesita leer antes de cambiar algo. El código dice qué hace la app; aquí se explica por qué y hacia dónde va.

| Carpeta | Para qué |
|---|---|
| [brand/](brand/frenkiieeee.md) | Marca Frenkiieeee: paleta, tipografía, mascota, tono |
| [architecture/](architecture/overview.md) | Cómo está montada la app y [cómo fluyen los datos](architecture/data-flow.md) |
| [specs/](specs/_template.md) | Un spec por funcionalidad, antes de construirla |
| [decisions/](decisions/001-applescript-no-mediaremote.md) | Decisiones difíciles de revertir, en formato corto (la [006](decisions/006-versionado-y-distribucion.md) trata de versiones y distribución) |
| [architecture/internals.md](architecture/internals.md) | Notas técnicas por dentro: lectura de la música, retardo, notch, permisos, trampas |
| [RELEASING.md](RELEASING.md) | Cómo se publica una versión |

## Hoja de ruta

| Fase | Contenido | Spec |
|---|---|---|
| 0 | Base: docs, harness de agentes, marca, mascota, `PlayerSource` | este directorio |
| 1 | Apple Music y letras en cualquier momento (atajo, menú, inactividad) | [001](specs/001-apple-music.md), [002](specs/002-lyrics-anywhere.md) |
| 2 | Ajustes nuevos | [003](specs/003-settings.md) |
| 3 | Motor de personalización de letras y reloj | [004](specs/004-lyrics-theme.md) |
| 3 (v1) | Estilos, reloj, portada difuminada, portada a la derecha | [004](specs/004-lyrics-theme.md) |
| 4 | Notch: música, widgets, bandeja, HUD, notificaciones, tamaño y estilos, vistas previas (pendiente de probar con los permisos reales) | [005](specs/005-notch.md), [006](specs/006-notifications.md) |
| 1b | Reproductor, salir con Esc o clic, portada centrada | [007](specs/007-player-controls.md) |
| 1c | Cambio de canción animado, con y sin letra | [008](specs/008-song-transition.md) |
| 4b | Crear eventos y recordatorios desde el notch | [009](specs/009-quick-add.md) |
| 5 | Versión, DMG, Homebrew, ajustes ordenados y restaurar | [010](specs/010-release-and-settings.md) |
| 4c | Luz del teclado con un atajo propio (⌥F2 y ⌥F1) | [011](specs/011-keyboard-light.md) |
| 6 | Notarización con Developer ID | pendiente |

## Cómo usarlos con agentes

1. El agente lee `CLAUDE.md` (raíz) y este índice.
2. Para una funcionalidad nueva, rellena primero el spec con `.claude/agents/spec-writer.md`.
3. Después de implementar, `.claude/agents/swift-reviewer.md` revisa el diff contra las restricciones de `CLAUDE.md`.
4. `./scripts/verify.sh` debe pasar antes de entregar.
5. Si una decisión cambia, se actualiza el ADR o se crea uno nuevo, no se edita en silencio.
