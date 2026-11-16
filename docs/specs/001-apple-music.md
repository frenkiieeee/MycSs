# 001 Apple Music

Estado: implementado (sin probar con Music sonando)

## Objetivo
Las letras funcionan igual con Apple Music que con Spotify.

## No objetivos
Control de reproducción (play, pausa, siguiente). Letras propias de Apple: se siguen usando LRCLIB y NetEase.

## Datos
`AppleMusicSource: PlayerSource` con AppleScript contra la app `Music`. La portada llega como datos (`data of artwork 1`), no como URL: `PlayerSource.artworkURL()` se amplía o se añade `artworkData()`. `NowPlaying.Source.appleMusic` ya existe.

## Interfaz
Ajuste "Reproductor": automático, Spotify, Apple Music. En automático gana el que esté reproduciendo.

## Permisos y riesgos
Permiso de Automatización nuevo (Music). Actualizar `NSAppleEventsUsageDescription` en `build-app.sh`. Mismas trampas de AppleScript que Spotify (decimal con coma, variables reservadas): ver README.

## Verificación
`--selftest` con Music sonando; bloquear la Mac y ver letras.

## Cómo está hecho

`Player/AppleMusicSource.swift` y `Player/PlayerHub.swift` (elige el reproductor que suena y se queda con él mientras siga sonando; lee los reproductores en serie, nunca a la vez). La portada llega con `artworkData()`. Ajuste en General > Reproductor.

## Preguntas abiertas
- ¿Qué pasa si suenan los dos a la vez?
