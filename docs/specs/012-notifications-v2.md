# 012 Notificaciones v2: al instante, por app y sin el aviso doble

Estado: hecho (lectura al instante, reglas e historial probados con una base sintética y con la real; el cierre del aviso del sistema, sin probar con un aviso real: en esta Mac macOS no llegó a enseñar el de prueba)

## Objetivo
Que una notificación salga en el notch en cuanto llega, que se pueda decidir por app dónde se ve (notch, sistema o los dos) y que, mientras MycSs está activo, el aviso lateral del sistema se pueda ir quitando app por app. Los ajustes caben en una pantalla, sin instrucciones largas.

## No objetivos
Responder desde el notch, acciones de la notificación (botones de la app), sonido propio, guardar el historial en disco.

## Datos
- `NotificationsModel` sigue leyendo la base de `usernoted` (ver [006](006-notifications.md) y [ADR 003](../decisions/003-notificaciones.md)), pero ya no pregunta cada segundo: vigila la carpeta `db2` y el archivo `db-wal` con `DispatchSource` (el sistema avisa al escribir) y lee al momento. Un temporizador de 3 s queda de red por si un aviso se pierde.
- Historial en memoria: las 30 últimas que llegaron, con lo que se decidió con cada una. Desde la [015](015-notch-polish-and-tap.md) se guarda entre ejecuciones (ajuste, 50 como máximo).
- Reglas por app (`notchNotificationRules`, `bundleID -> regla`): **Notch y sistema**, **Solo notch** (se quita el aviso del sistema) y **Solo sistema** (MycSs no la enseña). Una regla para las apps nuevas (`notchNotificationDefault`, por defecto «Notch y sistema», que es lo de antes).
- Las apps de la lista salen de la propia base (las que tienen notificaciones guardadas) y del historial.

## Interfaz
- Notch cerrado: icono de la app, el nombre y, si llegan varias seguidas de la misma app, el número («WhatsApp · 3»). La duración se elige (2 a 12 s). «Mostrar el contenido» se puede apagar: entonces solo sale «Nueva notificación».
- Widget **Notificaciones** en el notch abierto: las últimas, con la hora; un clic abre la app; «Borrar» vacía el historial.
- Ajustes, Notch, pestaña **Avisos**: interruptor, estado del permiso en una línea con un único botón, duración, contenido, «Para las apps nuevas» y la lista de apps con su regla. El texto largo de los pasos va en un desplegable.

## Quitar el aviso del sistema
macOS no deja impedir el aviso. Con **Accesibilidad** (la que ya usan las teclas), MycSs busca el aviso en el proceso `NotificationCenter` justo después de leer la notificación y pulsa su acción de cerrar. Se reconoce por el subrol `AXNotificationCenter*` o por una acción cuyo nombre o descripción diga cerrar (en varios idiomas), y se comprueba que el texto coincide con la notificación antes de cerrarla. Se busca durante 3 s como mucho.
- Consecuencia: la notificación también sale del Centro de notificaciones (queda en el historial del notch).
- Es experimental: el árbol de Accesibilidad del aviso cambia entre versiones de macOS. Cada intento deja una línea en el log (`banner: ...`) y `--banner-probe` vuelca el árbol para ajustarlo.

## Permisos y riesgos
Acceso total al disco (ya pedido) y Accesibilidad para quitar el aviso. Sin red.

## Verificación
- `--notification-selftest`: base sintética; llegada sin esperar al temporizador (menos de 0,5 s), reglas, historial y agrupación.
- `./scripts/verify.sh --notch`.
- A mano: una notificación real de una app con la regla «Solo notch» y ver que el aviso lateral se cierra; mirar `banner:` en el log.

## Preguntas abiertas
- ¿Mover las notificaciones al Centro sin cerrarlas, si Apple expone una acción para ello?
