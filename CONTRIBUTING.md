# Contribuir a MycSs

Gracias por querer ayudar. MycSs es un proyecto personal con reglas claras para mantenerlo estable.

## Compilar
Solo hacen falta las Command Line Tools de Xcode (no hay `.xcodeproj`).

```bash
./build-app.sh              # MycSs.app
./scripts/verify.sh         # compila, autoprueba y comprueba los enlaces de docs
./scripts/verify.sh --notch # además abre el notch real y pulsa sus controles
```

## Reglas del código
- Swift 5 language mode, macOS 15 o superior, sin `@State` (usa `@Observable` y `@Bindable`).
- El notch no toca `ignoresMouseEvents`; no se copia código de boring.notch (GPL-3.0).
- Los ajustes viven en `UserDefaults`: toda página de ajustes lee `SettingsRevision` para redibujarse.
- Un cambio de comportamiento lleva antes un spec en `docs/specs/` (plantilla en `_template.md`); una decisión cara de revertir, un ADR en `docs/decisions/`.

## Commits
`tipo(ámbito): descripción` en inglés, minúsculas, una línea, sin cuerpo (`feat(notch): add quick add window`).

## Versiones
Ver `docs/RELEASING.md` y `CHANGELOG.md`.
