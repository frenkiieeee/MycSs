# Publicar una versión

1. Ve anotando los cambios bajo `## [Unreleased]` de `CHANGELOG.md` mientras trabajas (`./scripts/changelog.py check` dice si hay algo). No hace falta escribir la sección de la versión: lo hace el script.
2. Haz commit de todo lo pendiente (el árbol debe estar limpio).
3. `./scripts/release.sh x.y.z` comprueba, sube `VERSION`, convierte `[Unreleased]` en `## [x.y.z] - fecha` (con los enlaces de comparación), ejecuta `verify.sh --notch` y genera `dist/MycSs-x.y.z.dmg` con su `.sha256`.
4. Ejecuta a mano lo que imprime al final: commit de `VERSION` y `CHANGELOG.md`, `git tag -a vx.y.z`, `git push origin main --tags`.
5. El workflow `release.yml` construye el DMG, crea la release con las notas del changelog y, en un segundo trabajo, apunta `Casks/mycss.rb` a la versión nueva con la suma del archivo publicado (un commit del bot en `main`). No hay que copiar nada a ningún tap: ver [009](decisions/009-tap-en-el-repositorio.md).

## Rama principal: nightly

Cada push a `main` (salvo cambios solo de documentos o de `Casks/`) ejecuta `nightly.yml`, que reemplaza la pre-release `nightly` con un DMG nuevo. Quien instaló `mycss@nightly` lo recibe con `brew upgrade --cask --greedy-latest mycss@nightly`.

## Reglas de versión
Ver `docs/decisions/006-versionado-y-distribucion.md`.

## Permisos tras actualizar
La firma cambia entre releases (identidad local o ad-hoc). macOS puede olvidar Accesibilidad y Acceso total al disco: hay que volver a concederlos. Con un Developer ID dejaría de pasar.

## Notarizar (cuando haya cuenta)
Firma con `CODESIGN_IDENTITY="Developer ID Application: ..."` y guarda un perfil: `xcrun notarytool store-credentials mycss`. Luego `NOTARY_PROFILE=mycss ./scripts/make-dmg.sh`.
