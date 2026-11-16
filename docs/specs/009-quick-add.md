# 009 Crear eventos y recordatorios desde el notch

Estado: implementado (la ventana real sin probar con teclado, la Mac está bloqueada)

## Objetivo
Al pulsar la fecha del widget de calendario (el mes y el año de la cabecera), crear un evento o un recordatorio para el día elegido sin salir del notch.

## No objetivos
Editar o borrar lo creado, repetición, alarmas, invitados, elegir calendario (se usa el de por defecto de la Mac).

## Datos
- `AgendaModel.createEvent` guarda un `EKEvent` en el calendario por defecto; `RemindersModel.createReminder`, un `EKReminder` en la lista por defecto. Los dos usan el permiso completo que ya se pide al abrir cada widget, así que no hay permisos nuevos.
- En `--demo` solo se añaden a la lista en memoria.

## Interfaz
Una ventana pequeña bajo el notch (`QuickAddPanel`), aparte del notch porque este nunca es la ventana de teclado y no podría recibir texto. Tiene: selector Evento o Recordatorio, campo de título con el foco, día, hora, duración (evento) o «con hora» (recordatorio), «Todo el día» (evento), Cancelar y Crear. Intro crea, Esc o un clic fuera cancela. Si falta el permiso lo dice y lo pide.

## Permisos y riesgos
Ninguno nuevo. La ventana no activa la app. Si no hay calendario o lista por defecto, muestra el error y no cierra.

## Verificación
`./scripts/verify.sh --notch` (crea un evento y un recordatorio en demo y comprueba que salen en sus listas). La ventana con teclado real hay que probarla a mano.

## Preguntas abiertas
- ¿Elegir calendario o lista?
- ¿Reconocer texto como «mañana 5pm comer»?
