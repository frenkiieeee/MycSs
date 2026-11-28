# 018 El notch abre siempre al principio y «Avisos» solo guarda lo pendiente

Estado: hecho

## Objetivo
Dos arreglos de uso diario. Al abrir el notch se ve siempre el principio (la página de inicio y su primer widget), no donde se dejó. Y «Avisos» deja de acumular notificaciones que el usuario ya vio, las haya atendido en el notch o en cualquier otro sitio.

## No objetivos
- Recordar en qué pestaña se estaba (se decidió que no): no hay ajuste para ello.
- Borrar nada del Centro de notificaciones de macOS: MycSs solo lee esa base.
- Marcar avisos como leídos y conservarlos: un aviso atendido sale de la lista (spec [015](015-notch-polish-and-tap.md)).

## Datos
- **Al abrir**: `NotchModel.open` pone `tab = .home` y `widget` = el primer widget activo de Ajustes, salvo que quien abre pida otra pestaña (arrastrar archivos abre la estantería). Se hace al abrir y no al cerrar, para que la animación de cierre no cambie de página. Abrir con el notch ya abierto no mueve nada.
- **Qué cuenta como «ya visto»**, en `NotificationsModel`:
  1. Abrirlo desde el notch o el widget (ya existía).
  2. Quitarlo con la cruz de su fila o con el cubo (nuevo: la cruz).
  3. **Que ya no esté en el Centro de notificaciones**: se descartó el aviso, se pulsó su banner, o la app lo retiró al leer el mensaje (Mensajes, Mail y otras lo hacen). Cada vez que se escribe la base se comprueba qué `rec_id` del historial siguen en la tabla `record` y se quitan los que no. Si la consulta falla no se quita nada.
  4. **Pasar a la app del aviso**: al activarse una app (`NSWorkspace.didActivateApplicationNotification`) se quitan los avisos que había de ella.
  5. **El tiempo**: pasadas 24 horas un aviso sale solo (sirve cuando no se puede leer la base, o al cargar el historial guardado).
- El historial guardado en disco se limpia igual al arrancar el lector, en cuanto la base se puede leer.

## Interfaz
- Cada fila del widget «Avisos» tiene una cruz al apuntarla (sustituye a la hora) que la quita sin abrir la app. El cubo de la cabecera sigue vaciando todo.
- El icono de «Avisos» en la fila de widgets lleva un punto con el número de avisos pendientes.

## Permisos y riesgos
- Sin Acceso total al disco no se puede leer la base: solo actúan la cruz, abrir, activar la app y las 24 horas.
- Quitar al activar la app es una decisión de producto: cambiar a una app sin haber mirado su aviso lo deja fuera de la lista. Es lo esperado cuando se va a leer, y el aviso sigue en el Centro de notificaciones.

## Verificación
- `--notification-selftest`: borrar un registro de la base de prueba lo quita del historial; uno viejo sale al cargar; activar una app quita los suyos.
- `--selftest`: abrir el notch vuelve a la página de inicio y al primer widget.
- `./scripts/verify.sh --notch`.

## Preguntas abiertas
- ¿Un ajuste «Recordar la pestaña» para quien lo prefiera? De momento no.
