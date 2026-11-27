# Changelog

All notable changes to MycSs are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Macs and screens without a notch (a notch-less MacBook, an external monitor): the
  notch now sits at the very top, inside the menu bar and as tall as it, and stays
  invisible until there is music, a notification or an indicator to show (or it can be
  a floating island under the bar, round on every side). Notch,
  Aspecto, "Pantallas sin notch": the shape (top of the screen or island), what it
  does at rest (nothing, or an always visible pill) and the width of its zone. It opens
  from the top centre edge of the screen, or from the new "Abrir el notch" item of the
  menu. The settings preview can show "Con notch" or "Sin notch" to try it on any Mac.
  The old fixed 170x28 pill, taller than the menu bar, is gone.
- Notch surfaces: besides the plain black, the notch can be **glass** (it blurs what is
  behind it, with a sheen and a rim of light) or **tinted glass** (the accent colour
  poured into it), with its own transparency and roundness of the corners (Notch,
  Aspecto). The idle notch stays black so it still joins the cut-out. Two new notch
  styles, "Cristal" and "Isla" (amber tinted glass, large corners, ring volume), and
  three new accents (amber, sky, rose). All of it is saved in your own styles, so a
  combination can be kept as a template.
- A ruler for the timer, like the iPhone's island: drag it sideways to pick the minutes
  and press "Iniciar" (Notch, Aspecto, Temporizador; "Isla" uses it).
- Homebrew from this very repository, always up to date: `brew tap frenkiieeee/mycss
  https://github.com/frenkiieeee/MycSs`, then `brew install --cask mycss` for the
  numbered releases or `mycss@nightly` for what is on `main` (rebuilt on every push,
  `brew upgrade --cask --greedy-latest mycss@nightly`). The release workflow points
  the stable cask at each new release by itself.
- `scripts/changelog.py` (check, release, notes): the release turns `[Unreleased]` into
  the new version with its date and links, and its notes become the GitHub release.
- The notifications the notch showed are kept between runs (the last 50, in a file only
  the user can read, off with "Recordar el historial al reiniciar"). Opening one takes it
  out of "Avisos"; the widget header counts what is left.
- The clipboard widget keeps pictures (a screenshot copied with Ctrl, an image copied
  from a page or the Finder), shown big over the list when the pointer is on one, and a
  button to clear it (the widget is titled "Copiado" now so it fits).
- The browser as a player: what plays in a tab of Chrome, Safari, Brave, Edge, Arc,
  Vivaldi, Firefox, Zen, Floorp, LibreWolf or Waterfox shows and can be controlled like
  Spotify, with the tab's icon as the cover. "Automático" includes it (General, Player,
  can be turned off; choosing "Navegador" always reads it); Chrome and
  the like need "Allow JavaScript from Apple Events", Firefox and Zen need nothing (they
  are read from the system's Now Playing, with a small library of ours that `perl`
  loads, and the favicon comes from the browser's saved session). A click on the player's icon on the cover (or "Reproductor" in the menu)
  moves to the next player that has something.
- Notifications per app: in the notch and the system, the notch only (the system's
  banner is closed with Accessibility, experimental) or the system only, with a rule
  for new apps. Several in a row from one app are counted, the text can be hidden,
  and a new "Notificaciones" widget keeps the last ones. Their own settings tab, "Avisos".
- Notch timing: open on hover or on click, and how long it waits to open and to close.
  Dragging files: on or off, how long to hold them over the notch, and how wide the zone is.
- A button to clear the saved covers (General, Player).
- A shortcut of its own for the keyboard light: Option+F2 raises it and Option+F1
  lowers it (it works with the brightness keys or with plain F keys). Each shortcut
  can be recorded again, cleared or restored. The change shows in the notch, and on
  the lock screen, with the volume and brightness indicator (same style, numbers and
  motion) and its own icon, a keyboard with rays of light. It needs Accessibility and
  a Mac with a keyboard light; Notch settings, tab "Teclas".
- The volume and brightness indicator also shows on the lock screen (top right),
  where the notch is hidden, in the same style, numbers and motion as the notch. It
  can be turned off and has six animations (fade, slide, grow, pop, drop, blur).

### Changed
- The timer drops under the closed notch, like a notification, instead of squeezing the
  time into its side: it fits at any size of the notch, and the sides keep the music.
- The names and icons of the apps in notifications are looked up once, not on every redraw.
- Notifications reach the notch as soon as macOS stores them (about 50 ms; before, up
  to a second): the database is watched instead of read every second.
- With the notch open, a new song animates: the cover fades in over the old one
  with a small beat, and the title and artist are replaced with the song change
  animation (also for songs skipped in a row).

### Fixed
- The "Minimal" style left the cover stuck to the top while the lyrics were in the
  middle; without the clock the cover is now centred with them.
- The open notch no longer shifts when the notifications widget is shown: it is one row
  shorter, titled "Avisos", and its "Borrar" button is in the header.
- With Spotify's DJ, a song could keep the previous singer's cover for good: a cover
  found in the cache left no URL to compare with, so Spotify's late URL was taken as the
  new song's and saved. Every player URL is now remembered with its song, the title is
  read together with the artist, and the old cache is dropped once. The DJ's own
  segments ("Up next", a `spotify:media:` item) are no longer searched for lyrics or
  covers, and each one has its own cover key.
- The log no longer grows without bound: one repeated lock screen line is written once
  every 500 times, and past 5 MB the file moves to `MycSs.log.1`.
- The shelf opened by itself with any click and hold near the notch after a first drag
  of files (the system keeps the last dragged files); now only a real drag counts.

## [0.2.5] - 2026-11-16

First packaged release: installable from a disk image, a script or Homebrew.

### Added
- Lyrics on the lock screen and as a full screen mode (global shortcut, menu, idle),
  word by word, for Spotify and Apple Music. Sources: LRCLIB, NetEase, QQ Music.
- Theme from the album cover, animated backgrounds, clock with auto hide, and a
  small `@frenkiieeee` signature that fades with inactivity.
- Animated song change (fade, slide or cinematic) that covers songs with and
  without lyrics.
- Player controls under the cover, Esc or a click outside to leave, and the cover
  centred when a song has no lyrics.
- The notch: music with cover and visualiser, peek on song change (to the sides
  or down, with size and duration), volume and brightness indicator (bar, slider,
  ring, segments), notifications, shelf, and widgets (calendar, reminders, timer,
  system, clipboard). It can also show on other screens.
- Create events and reminders by pressing the date of the calendar widget.
- Styles for the lyrics and the notch, with your own styles (create, edit, delete),
  live previews and viewing a style without applying it.
- Settings window with sidebar, live previews and a quit button.
- Semantic versioning (`VERSION`, `MycSs --version`), disk image builder
  (`scripts/make-dmg.sh`), `install.sh`, `scripts/uninstall.sh`, a Homebrew cask,
  CI and release workflows.
- Open at login (System login items) and a manual check for updates in About.

### Changed
- Minimum macOS is 15 in the app bundle too (it said 14 by mistake).

### Fixed
- Hiding the menu bar icon no longer ends the app (stack overflow in the status
  item observer).
- Settings controls redraw when clicked and the running notch follows the settings.
