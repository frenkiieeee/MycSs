# 010 Instalación, versiones y orden de los ajustes

Estado: implementado (ajustes y DMG sin ver en la ventana real, la Mac está bloqueada)

## Objetivo
Que MycSs se pueda instalar y actualizar sin compilar, con versión semántica, y que los ajustes estén ordenados y se puedan restaurar.

## No objetivos
Notarización (gancho listo), actualización automática, tests con XCTest.

## Datos
- `VERSION` es la fuente de la versión; `build-app.sh` la escribe en el `Info.plist` (`CFBundleVersion` = número de commits). Ver ADR 006.
- Abrir al iniciar sesión: `SMAppService.mainApp`, sin archivos propios.
- Buscar actualizaciones: una consulta manual a la API pública de GitHub.
- Restaurar: borra de `UserDefaults` las claves de `StyleDomain.keys`; `PresetUndo` guarda el estado anterior para «Deshacer».
- Las claves de ajustes viven en `SettingKey`, y `StyleDomain.keys` las usa, así que un nombre mal escrito no compila.

## Interfaz
- General: «Inicio» (abrir al iniciar sesión) y «Restaurar valores» (letras y reloj, notch, todo, con «Deshacer»).
- Letras: ahora incluye «Cambio de canción» (antes en Apariencia).
- Notch: interruptor y pantallas arriba, y un selector de seis partes (Estilos, Aspecto, Música, Volumen, Widgets, Sistema) en lugar de un scroll largo.
- Acerca de: versión con build, buscar actualizaciones, GitHub, registro y salir.

## Permisos y riesgos
- Abrir al iniciar sesión solo funciona desde `MycSs.app` (idealmente en Aplicaciones); si no, la página lo explica.
- Sin notarización, macOS pierde Accesibilidad y Acceso total al disco tras cada actualización.

## Verificación
`./scripts/verify.sh --notch` (incluye la prueba de claves y restaurar en `--settings-snapshot`), `./scripts/make-dmg.sh`, `./install.sh --source-dir . --prefix /tmp/x`, `./scripts/uninstall.sh --prefix /tmp/x --yes`. La ventana de ajustes real hay que mirarla a mano.

## Preguntas abiertas
- ¿Developer ID para notarizar?
