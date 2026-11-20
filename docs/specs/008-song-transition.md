# 008 Cambio de canción

Estado: implementado (movimiento real sin ver con la Mac bloqueada)

## Objetivo
Que el paso de una canción a otra se vea fluido en la pantalla de letras, tanto si las dos canciones tienen letra como si una no la tiene, sin cortes ni parpadeos.

## No objetivos
La animación de «canción nueva» del notch cerrado (ver spec 005). Con el notch **abierto** sí aplica: la portada se funde con un pequeño latido y el título y el artista cambian con la misma animación. El fondo y los colores (ya hacen su transición desde la portada).

## Datos
- `AppSettings.songTransition`: `off`, `fade`, `glide`, `cinematic` (por defecto `cinematic`).
- `AppSettings.songTransitionSeconds`: de 0,25 a 1,8 s (por defecto 0,8).
- `LyricsViewModel.lyricsReveal` (0 a 1) y `lyricsLeaving`: cuánto se ve la columna de letras y hacia dónde se va.

## Interfaz
Orden de una canción a otra con letra: la letra vieja se queda un momento y sale (sube y se desvanece, en el 45 % del tiempo); la portada nueva entra sobre la vieja (con zoom suave); el título y el artista se cambian con un desplazamiento corto; cuando llega la letra nueva entra desde abajo.
- `fade`: solo opacidad. `glide`: opacidad y desplazamiento. `cinematic`: además desenfoque y zoom.
- Sin letra en la canción nueva: la letra vieja sale y la portada pasa al centro (animación de 0,75 s que ya existía).
- Sin letra a con letra: la portada vuelve a la izquierda y la letra entra.
- Sin letra a sin letra: solo cambian portada y título.
- Si llega otra canción mientras sale la anterior, la salida se reinicia sin saltos.

## Permisos y riesgos
Ninguno. La letra vieja no se actualiza mientras sale (queda congelada), y la nueva no se publica hasta que termina la salida.

## Verificación
`--settings-snapshot` (el estado final y los ajustes siguen igual), botón «Cambiar canción» en la vista previa de Letras y Apariencia. El movimiento real hay que verlo a ojo.

## Preguntas abiertas
- ¿Mostrar una barra fina de «cargando letra» si tarda más de 2 s?

## Indicador de volumen en el bloqueo
Con la pantalla **bloqueada** (no en el salvapantallas de letras, donde macOS dibuja el suyo) el overlay dibuja el indicador de volumen y brillo arriba a la derecha, con el estilo del notch. Ajustes: `lockHUD` (interruptor) y `lockHUDAnimation` (fundido, deslizar, crecer, rebote, caída con rebote, desenfoque), en Apariencia. Necesita el notch y su indicador activos y Accesibilidad. «Probar volumen» en la vista previa lo enseña.
