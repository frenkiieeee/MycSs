# Publicar una versión

1. Escribe la sección `## [x.y.z] - fecha` en `CHANGELOG.md` (pasa lo de `[Unreleased]` a ella).
2. Haz commit de todo lo pendiente (el árbol debe estar limpio).
3. `./scripts/release.sh x.y.z` comprueba, sube `VERSION`, ejecuta `verify.sh --notch`, genera `dist/MycSs-x.y.z.dmg` con su `.sha256` y rellena el cask.
4. Ejecuta a mano lo que imprime al final: commit de `VERSION`, `CHANGELOG.md` y el cask, `git tag -a vx.y.z`, `git push origin main --tags`.
5. El workflow `release.yml` construye el DMG y crea la release al llegar la etiqueta. Si prefieres subirlo tú, usa el de `dist/`.
6. Copia `packaging/homebrew/mycss.rb` al tap `frenkiieeee/homebrew-mycss` (`Casks/mycss.rb`).

## Reglas de versión
Ver `docs/decisions/006-versionado-y-distribucion.md`.

## Permisos tras actualizar
La firma cambia entre releases (identidad local o ad-hoc). macOS puede olvidar Accesibilidad y Acceso total al disco: hay que volver a concederlos. Con un Developer ID dejaría de pasar.

## Notarizar (cuando haya cuenta)
Firma con `CODESIGN_IDENTITY="Developer ID Application: ..."` y guarda un perfil: `xcrun notarytool store-credentials mycss`. Luego `NOTARY_PROFILE=mycss ./scripts/make-dmg.sh`.
