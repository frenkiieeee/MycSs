# Changelog

All notable changes to MycSs are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
