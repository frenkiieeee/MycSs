# 003 Ajustes nuevos

Estado: primera versión (barra lateral, mascota, reproductor, atajo, inactividad; falta vista previa en vivo y búsqueda)

## Objetivo
Un panel de ajustes con la identidad de MycSs, rápido de usar, con vista previa en vivo.

## No objetivos
Cambiar el modelo de datos: eso es el spec [004](004-lyrics-theme.md).

## Datos
Lee y escribe `AppSettings` (hoy claves sueltas en `UserDefaults`).

## Interfaz
Barra lateral por secciones, búsqueda, vista previa del overlay con la mascota, presets. Hoy es un `TabView` + `Form` de 3 pestañas en `App/SettingsView.swift`. Marca según `brand/frenkiieeee.md`.

## Permisos y riesgos
Sin `@State` (CLAUDE.md): estado compartido en clases `@Observable`.

## Verificación
Captura del panel; cada ajuste se refleja al instante en el overlay.

## Preguntas abiertas
- Secciones y orden.
