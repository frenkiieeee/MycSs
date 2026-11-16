# 005 Notch

Estado: música, widgets (calendario, recordatorios, temporizador, sistema, portapapeles), bandeja, volumen y brillo, visualizador con audio real, notificaciones, tamaño y estilos configurables, vistas previas en los ajustes. Sin verificar con permisos reales: notificaciones (Acceso total al disco), teclas (Accesibilidad), Recordatorios y audio.

## Objetivo
Un notch propio, con estética MycSs: música, acceso rápido al calendario y otras vistas rápidas configurables. Inspiración de producto en boring.notch, sin copiar código ([ADR 002](../decisions/002-gpl-boringnotch.md)).

## No objetivos
Extensiones de terceros en la primera versión.

## Datos
`NotchPanel` en la parte superior (`NSScreen.safeAreaInsets` para detectar el notch; píldora si no hay). Estados: cerrado, aviso, expandido. Módulos alimentados por `NotchEventBus`: música (`PlayerSource`), calendario (EventKit), teclas de volumen y brillo (`CGEventTap`, consume la tecla y dibuja su propio HUD).

## Interfaz
Colores, animaciones, tamaños y módulos configurables.

## Permisos y riesgos
Accesibilidad o Monitorización de entrada para el HUD. El brillo usa API privada. **Los permisos concedidos se pierden con la firma ad-hoc al recompilar: hace falta firma estable antes de esta fase.**

## Verificación
Con y sin notch; varios monitores.

## Cómo está hecho (v3)

La v1 y la v2 usaban zonas de clic calculadas a mano y una ventana que cambiaba su `ignoresMouseEvents`. En uso real los botones no respondían, el calendario no pedía permiso y las animaciones eran saltos. Se rehízo tomando la **estructura** de boring.notch (sin copiar su código, GPL-3.0; ver [ADR 002](../decisions/002-gpl-boringnotch.md) y [ADR 005](../decisions/005-notch-arquitectura.md)).

- `NotchPanel`: tamaño fijo, transparente, nivel `.mainMenu + 3`, sin tocar `ignoresMouseEvents`. `NotchHostingView.acceptsFirstMouse` devuelve true.
- `NotchModel` (`@Observable`): `isOpen`, `tab`, `isPeeking`, `hud`. Un solo sitio para abrir, cerrar, vistazo e indicador. El hover abre a los 90 ms y cierra a los 180 ms, y el cierre se anula si el puntero sigue dentro por posición.
- `NotchView`: una forma (`NotchShape`) con el tamaño animado por un muelle (abrir 0,40/0,78; cerrar 0,36/0,94). El contenido se compone a su tamaño final y la forma lo descubre. `blurReplace` entre estados; `matchedGeometryEffect` para la portada y la píldora de las pestañas.
- Tamaños: cerrado = hueco; con música +58 pt por lado; vistazo +70 pt y una fila; indicador +96 pt por lado; abierto 640 x 176 a escala 0,86 por defecto (ajustable de 0,7 a 1,3; la ventana ya mide lo del máximo y no cambia de tamaño). Inicio: 60 % música, 40 % widget.
- Inicio: música (portada con el icono del reproductor, barra con clic y arrastre, botones) y calendario de la semana. Bandeja: `ShelfModel`, soltar con `onDrop`, sacar con `onDrag`, AirDrop con `NSSharingService`.
- `NotchController`: alimenta al modelo desde fuera (canción, teclas, puntero) y es la red de seguridad del hover. Arrastrar archivos hacia el notch abre la bandeja.
- `VolumeWatcher`: escucha el volumen del dispositivo de salida; el volumen siempre se ve en el notch. `MediaKeyTap` (CGEventTap en `cghidEventTap`, Accesibilidad) quita el indicador del sistema y añade el brillo. `DisplayBrightness` usa `DisplayServices` (API privada).
- `AgendaModel`: EventKit con acceso completo, de 14 días atrás a 45 adelante (la tira muestra siete, centrada en el día elegido; dos dedos a los lados la recorren con un tic háptico por día, vía `ScrollCatcher`), `NSApp.activate` antes de pedir permiso (una app sin Dock puede no mostrar el diálogo si no está activa).
- `AudioReactor`: tap global de Core Audio y cinco bandas con filtros de un polo.
- Firma: `CODESIGN_IDENTITY` en `build-app.sh` y `scripts/make-dev-cert.sh`.
- Medido en este Mac: hueco de 185 x 32 pt centrado.

## Ampliaciones (lote 11)

- Widgets del 40 %: `NotchWidgets.swift` (+ `Notch/Widgets/*Model.swift`). Cada uno es un bloque con cabecera y selector de iconos; el elegido se recuerda.
- Notificaciones: `NotificationsModel` (SQLite, solo lectura, frescas de menos de 90 s, ignora las propias). Estado en `NotchModel.notification`; cerrado ensancha, abierto va en la cabecera.
- Ajustes: sección Notch con vista previa en vivo (`NotchPreviewState`, modelos en modo demo) y estilos con `PresetUndo`.
- Covers: `CoverProvider` (caché en disco, URL del reproductor, Deezer con puntuación, iTunes). `--cover-bench` mide el acierto.
- Icono de la barra de menú: `hideMenuBarIcon`, solo efectivo con el notch encendido.

## Verificación

`MycSs --demo --notch-selftest /tmp/n`: ventana real, clics reales de ratón sobre ella, fotogramas en mitad de la animación. Pasa: abrir, play/pausa (dos veces), siguiente, anterior, barra de progreso al 75 %, día del calendario, pestañas, cerrar y hover. **No cubre** el hover con un ratón físico ni el CGEventTap, que necesita Accesibilidad.

## Preguntas abiertas
