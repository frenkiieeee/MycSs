# 006 Notificaciones en el notch

Estado: lector hecho y probado con una base sintética; sin verificar con la base real (falta Acceso total al disco en la máquina de desarrollo)

## Objetivo
Mostrar las notificaciones en el notch al estilo de las Dynamic Island.

## No objetivos
Suprimir el banner nativo por código: macOS no lo permite. Ver [ADR 003](../decisions/003-notificaciones.md).

## Datos
Lectura de la base SQLite de `usernoted` (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`), que exige Acceso total al disco. Plan B: solo eventos propios de MycSs.

## Interfaz
Guía en los ajustes para poner los banners de las apps elegidas en "Ninguno" o usar un Focus propio.

## Permisos y riesgos
Acceso total al disco, que Apple anunció que endurecerá (2 oct 2026, sin fecha).

## Verificación
**Spike antes de construir:** comprobar que con banners en "Ninguno" y con Focus activo la notificación sigue escribiéndose en la base de datos. No está comprobado.

## Implementación
`NotificationsModel`: abre la base en solo lectura cada segundo, arranca desde el último `rec_id` (el historial no se muestra), decodifica el plist de `data` (`req.titl/subt/body`) y el nombre de la app desde la tabla `app`. `--notification-selftest` crea una base con el esquema real y comprueba lo anterior; `MYCSS_NOTIFICATION_DB` apunta el lector a otra base. Sigue sin comprobarse que con el aviso en «Ninguno» o con un Focus la fila se escriba.

## Preguntas abiertas
- ¿Qué apps cubrir primero?
