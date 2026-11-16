# 004 Tema de letras y reloj

Estado: estilos propios (crear, editar, borrar, en uso), reloj que se oculta solo, firma `@frenkiieeee` y vista previa en vivo hechos; falta el modelo `Codable` exportable y la ubicación libre de elementos

## Objetivo
Personalización amplia: posición de cada elemento, letras, fondos, animaciones. Reloj mejorado, con inspiración en la pantalla de bloqueo del iPhone. Por defecto, fuentes de Mac (SF Pro).

## No objetivos
Editor visual de arrastrar y soltar en la primera versión.

## Datos
`LyricsTheme: Codable` con layout, tipografía, fondo, animaciones y reloj. Se migra desde las claves actuales de `AppSettings`. Exportar e importar como JSON.

## Interfaz
Presets propios de la marca, ajustes por elemento, vista previa.

## Permisos y riesgos
Diseñar el modelo bien una vez: es lo que sostiene el resto. Mantener el rendimiento de la columna de letras (README, "Cómo se mueve la letra").

## Verificación
Migración sin pérdida de los ajustes actuales; capturas de varios presets.

## Preguntas abiertas
- Estilos de reloj a incluir.
