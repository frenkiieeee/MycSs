# 011 Luz del teclado con un atajo propio

Estado: implementado (la luz real responde en las pruebas; las teclas reales y el bloqueo sin probar a mano)

## Objetivo
Subir y bajar la luz del teclado con un atajo de MycSs. De base es **⌥F2** para subir y **⌥F1** para bajar, y el usuario puede grabar otra combinación para cada acción. El cambio se dibuja en el notch (y en la pantalla de bloqueo) con el mismo indicador que el volumen y el brillo, con su propio icono: un teclado con rayos de luz.

## No objetivos
Encender o apagar de golpe, luz automática por ambiente, apagado por inactividad, teclados externos, elegir el tamaño del paso. Los atajos del volumen y del brillo de la pantalla no cambian.

## Datos
- `KeyboardBacklight` (`Input/KeyboardBacklight.swift`) lee y escribe la luz con `KeyboardBrightnessClient`, de la librería privada `CoreBrightness`, cargada al ejecutar y por el runtime de Objective-C. Es la misma clase que usa macOS. Si la librería, la clase o los métodos no están, o el Mac no tiene luz de teclado, `isAvailable` es falso y el atajo no hace nada (la tecla sigue al sistema).
- `KeyChord` (`Input/KeyChord.swift`): una tecla virtual (`kVK_*`) y los modificadores (bits de Carbon). Se guarda como texto `código|modificadores|carácter`. «Sin atajo» se guarda como `none`.
- Ajustes: `keyboardLight` (activo, por defecto sí), `keyboardLightUp` (⌥F2) y `keyboardLightDown` (⌥F1). No forman parte de ningún estilo, y «Restaurar valores» no los toca, igual que el atajo de las letras.
- Un paso es 1/16 de la luz, igual que el volumen y el brillo.

## Teclas
- `MediaKeyTap` ya escucha `NX_SYSDEFINED` (donde llegan las teclas de brillo y volumen). Ahora también `keyDown` y `keyUp`, para el teclado en modo «F1, F2 como teclas estándar» y para cualquier combinación grabada.
- Una tecla multimedia se traduce a la F que lleva en un teclado Apple: brillo menos F1, brillo más F2, F7 a F9 anterior, reproducir y siguiente, F10 a F12 silencio y volumen. Así la misma combinación vale en los dos modos del teclado.
- La combinación se compara **exacta** (control, opción, mayúsculas y comando): ⌥⇧F1 sigue siendo el paso fino del brillo de la pantalla, no de la luz.
- La pulsación se traga solo si la luz cambió de verdad, y su soltado también. Mantener pulsado repite.
- Sin Accesibilidad el atajo no funciona (el sistema solo deja tragar teclas a las apps de confianza) y se dice en los ajustes. El filtro de `keyDown` descarta al instante lo que no es una F ni lleva un modificador; solo se compara el código de la tecla, no se guarda ni se envía nada.
- El atajo funciona mientras el notch está encendido o, con la Mac bloqueada, mientras el indicador del bloqueo esté activo. El permiso y el tap son los mismos que los de volumen y brillo.

## Interfaz
Ajustes, Notch, pestaña «Teclas» (antes «Volumen»): sección «Luz del teclado» con el interruptor, un grabador para subir y otro para bajar, «Restaurar ⌥F2 y ⌥F1» y el estado. El grabador usa el tap cuando está (así graba también las teclas de brillo) y, si no, un monitor local de teclado. Esc cancela; Suprimir quita el atajo. Una combinación necesita un modificador, salvo las teclas F.

El icono es `keyboard.fill` con `light.max` encima: los rayos suben de intensidad con el valor y se apagan en 0. Va con el indicador de siempre (barra, deslizador, anillo, segmentos, número, movimiento y entrada de los ajustes del notch; en el bloqueo, la animación elegida). La vista previa del notch tiene el momento «Teclado».

## Permisos y riesgos
Ninguno nuevo. La librería es privada: puede cambiar en una versión de macOS. Si pasa, el atajo se queda inactivo sin error y las pruebas lo dicen (`--selftest`).

## Verificación
- `--selftest-pure`: ida y vuelta del texto de la combinación, etiquetas, traducción de teclas multimedia, comparación exacta de modificadores y que ⌥⇧F1 no sea la luz.
- `--selftest`: lee la luz y escribe el mismo valor (no cambia nada); si hay luz, sube un paso y restaura.
- `--notch-selftest`: dibuja el indicador del teclado en el notch real (`-8b-keyboard.png`).
- `--notch-snapshot`: `-hud-keyboard.png`. `--settings-snapshot`: la escena «Teclado» de la vista previa.
- A mano, con la Mac desbloqueada: ⌥F2 y ⌥F1 cambian la luz y salen en el notch; grabar otra combinación y que la antigua vuelva al sistema; bloquear y repetir.

## Preguntas abiertas
- ¿Un paso elegible (8, 16 o 32 niveles)?
- ¿Mostrar también el indicador cuando otra app o las teclas físicas de luz cambian el valor?
