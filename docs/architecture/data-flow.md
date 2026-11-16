# Flujo de datos

## Hoy

```
Spotify.app
   │  AppleScript (rápido cada 200 ms, lento una vez por canción)
   ▼
SpotifySource : PlayerSource
   │  PlayerSnapshot / PlayerTrackMetadata
   ▼
SyncEngine (actor)  ── título nuevo ──▶ LyricsProvider (LRCLIB ∥ NetEase) ──▶ Lyrics
   │  posición interpolada
   ▼
LyricsViewModel (@Observable, @MainActor)  ◀── ThemeEngine ◀── portada (URL) ◀── PlayerSource.artworkURL
   ▼
OverlayRootView  ◀── AppSettings
   ▼
LockOverlayPanel (uno por pantalla)  ◀── LockState (bloqueo/desbloqueo)
```

Regla: el sondeo corre siempre, con la Mac desbloqueada también, para que al bloquear la letra ya esté cargada.

## Objetivo

```
PlayerSource (Spotify | AppleMusic)
   ▼
NowPlayingHub  elige la fuente activa
   ▼
SyncEngine ─▶ ViewModel ─▶ vistas de letras ◀── LyricsTheme (Codable, Fase 3)
                                   ▲
              OverlayPresenter: bloqueo | atajo | menú | inactividad  (Fase 1)

EventSource (calendario, notificaciones, teclas de volumen/brillo)
   ▼
NotchEventBus ─▶ NotchView / NotchPanel  (Fase 4)
```

## Contratos

- `PlayerSource`: lectura rápida (posición, estado, título), lectura lenta (artista, álbum, duración, URL), URL de portada. Ver `Sources/MycSs/Player/PlayerSource.swift`.
- Un reproductor nuevo es una conformancia nueva. Nada más en el flujo cambia.
- Los datos privados (qué suena, qué teclas se pulsan, notificaciones) no salen de la máquina. Solo se hacen peticiones de red para letras y portadas.
