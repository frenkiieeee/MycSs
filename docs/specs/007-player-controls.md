# 007 Reproductor, salida y portada centrada

Estado: implementado (clics y Esc sin probar con entrada real)

## Objetivo
Un reproductor completo bajo la portada, salir de las letras con Esc o con un clic fuera, y que la portada pase al centro cuando una canción no tiene letra.

## No objetivos
Cola, volumen, favoritos. Arrastrar la barra de progreso en la pantalla de bloqueo: allí solo hay clics.

## Datos
- `PlayerCommand` (play y pausa, siguiente, anterior, saltar) en `PlayerSource.send`, por AppleScript. `SyncEngine.perform` adelanta la posición y vuelve a leer a los 0,3 s.
- Zonas de clic: cada vista informa de su rectángulo con `.screenRegion` (coordenadas de pantalla, origen abajo a la izquierda) y `LyricsViewModel.handleClick` las consulta.
- Estado «sin letra»: `SyncEngine.lyricsNotFound`, con un reintento a los 8 s.

## Interfaz
Barra de progreso con tiempo transcurrido y total, anterior, un disco blanco con el icono que cambia entre play y pausa, y siguiente. Los iconos rebotan al pulsarse. La portada se centra con una animación suave de 0,75 s y vuelve a la izquierda si la letra llega después.

## Permisos y riesgos
Ninguno nuevo. Esc en la pantalla de bloqueo puede no detectarse, porque el bloqueo oculta el estado del teclado mientras se escribe la contraseña. El clic fuera sí funciona.

## Verificación
`--selftest` (texto de las órdenes), captura con `--demo` y `--demo-nolyrics`. Los clics y Esc necesitan prueba a mano.

## Preguntas abiertas
- ¿Mascota que cambie de expresión con el estado del reproductor?
