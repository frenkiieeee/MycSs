# 002 Letras en cualquier momento

Estado: implementado (cierre por entrada sin probar con teclado y ratón reales)

## Objetivo
Ver las letras fuera del lock screen: por atajo de teclado configurable, desde el menú de barra ("Letras") o tras un tiempo de inactividad.

## No objetivos
Un `.saver` del sistema (ScreenSaver.framework). Ver ADR [004](../decisions/004-modo-salvapantallas-propio.md).

## Datos
`OverlayPresenter` separa qué se dibuja (`OverlayRootView`) de cuándo y cómo se presenta. Modos: bloqueo (click-through, SkyLight) y presentación (ventana normal, se cierra con tecla o ratón). Atajo con Carbon `RegisterEventHotKey`, que no pide permisos. Inactividad con el tiempo de inactividad del sistema.

## Interfaz
Ajuste de atajo con grabador de teclas, opción de menú, tiempo de inactividad.

## Permisos y riesgos
Ninguno nuevo. Riesgo: el modo presentación no debe heredar el comportamiento click-through del lock screen.

## Verificación
Atajo abre y cierra; el preview actual (`--preview`) pasa a ser este modo.

## Cómo está hecho

- `LockOverlayController.showPresentation()` reutiliza los paneles con `isPresentation = true` (nivel `.screenSaver`, `.fullScreenAuxiliary`, traga el clic que lo cierra). Sin vigilar teclado ni ratón: no hay pista de contraseña.
- Se cierra cuando `CGEventSource.secondsSinceLastEventType` baja de 0,3 s, pasado 1,2 s de gracia. No necesita permisos.
- Atajo: `Input/HotKeyManager.swift` (Carbon) y `Input/HotKeyRecorder.swift`. Por defecto ⌃⌥L.
- Inactividad: solo si hay música sonando; por defecto desactivada.
- Límite conocido: el cursor sigue visible, la app no puede ocultarlo sin estar activa.

## Preguntas abiertas
- ¿El atajo cierra con el mismo atajo, con Esc o con cualquier tecla?
