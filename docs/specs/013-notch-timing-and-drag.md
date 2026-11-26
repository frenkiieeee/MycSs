# 013 Apertura, cierre y arrastre de archivos a medida

Estado: hecho (la lógica, probada con una mesa de arrastre simulada; el arrastre real desde el Finder, sin probar a mano)

## Objetivo
Que el usuario elija cuánto tarda el notch en abrirse y en cerrarse con el puntero (o que solo se abra con un clic), y que arrastrar archivos no lo abra por accidente.

## No objetivos
Gestos del trackpad, abrir con un atajo.

## Datos
Ajustes nuevos (no forman parte de los estilos): `notchOpenTrigger` (al pasar o con clic), `notchOpenDelay` (0 a 1 s, 0,1), `notchCloseDelay` (0 a 2 s, 0,2), `notchDragOpen` (sí), `notchDragDelay` (0 a 1,5 s, 0,35) y `notchDragZone` (pequeña, normal, grande).

## El fallo de hoy
El notch creía que se arrastraban archivos siempre que el botón del ratón estaba pulsado y la mesa de arrastre del sistema tenía archivos de un arrastre **anterior** (esa mesa no se vacía). Seleccionar texto o mover una ventana cerca del notch abría la bandeja. Ahora un arrastre es real solo si la mesa cambió **después** de pulsar el botón (`DragTracker`, con un monitor global de clics que no pide permisos) y el puntero sigue en la zona durante la espera elegida.

## Interfaz
Ajustes, Notch, pestaña Aspecto, sección «Apertura y cierre»: «Abrir» (al pasar el puntero o con un clic), «Esperar antes de abrir», «Esperar antes de cerrar», «Abrir la bandeja al arrastrar archivos», «Espera al arrastrar» y «Zona de arrastre».

## Permisos y riesgos
Ninguno nuevo: el monitor de clics global no lee teclas.

## Verificación
`--selftest-pure` (la lógica de `DragTracker` con una mesa simulada) y `./scripts/verify.sh --notch` (la prueba del notch usa las esperas).
