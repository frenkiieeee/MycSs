# 006 Versionado semántico y distribución sin notarizar

Estado: aceptada (2026-11-16)

## Contexto
MycSs solo se podía instalar compilándolo. Hace falta una versión fiable, una forma sencilla de instalar y actualizar, y no hay cuenta de Apple Developer (99 USD al año) para notarizar.

## Decisión
- **SemVer** `MAJOR.MINOR.PATCH`, con `VERSION` como única fuente. Mayor: un cambio que rompe los ajustes guardados o exige acción del usuario. Menor: funciones nuevas compatibles. Parche: arreglos. Antes de 1.0.0 un menor puede ajustar cosas pequeñas, y se dice en el CHANGELOG.
- Etiquetas de git `vX.Y.Z`. `CFBundleVersion` es el número de commits.
- Distribución: DMG en GitHub Releases, `install.sh` y un cask de Homebrew en un tap propio. Sin notarizar: la primera apertura pide clic derecho > Abrir; `install.sh` y el cask explican o quitan la cuarentena.
- Dejar un gancho `NOTARY_PROFILE` en `make-dmg.sh` para cuando haya Developer ID.
- Las actualizaciones las comprueba el usuario con un botón en «Acerca de», nunca en segundo plano.

## Consecuencias
- La firma local cambia entre releases, así que macOS pierde Accesibilidad y Acceso total al disco al actualizar; se documenta.
- Sin notarizar, Gatekeeper avisa a quien descarga el DMG con un navegador.
- Cambiar a Developer ID más adelante no rompe nada: solo cambia la identidad de firma.
