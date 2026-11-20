<div align="center">

<img src="Assets/Mascot/png/mycss-feliz-512.png" width="140" alt="The MycSs mascot">

# MycSs

**A creative layer for your Mac.** Synced, word by word lyrics on the lock screen, and a notch that gathers music, calendar and more.

![Version](https://img.shields.io/badge/version-0.2.5-FFD400?style=flat-square)
![macOS](https://img.shields.io/badge/macOS-15%2B-0B0B0F?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-3A3A46?style=flat-square)

[Español](README.md)

</div>

---

## What it does

- **Lyrics on the lock screen** for Spotify and Apple Music, highlighted word by word, with the cover, a clock and an animated background that follows the album colours. It also opens as a screensaver (shortcut ⌃⌥L, menu bar, or after idle time).
- **A notch** with cover and visualiser, the title on song change, a volume, brightness and keyboard light indicator (the light has its own shortcut, Option+F2 and Option+F1, which you can change), notifications, a file shelf and widgets (calendar, reminders, timer, system, clipboard). It can show on other screens too.
- **Customisable**: fonts, highlight effect, clock, backgrounds, animations, notch size and motion. Everything is saved as **styles** you can preview before applying.

## Requirements

macOS 15 or later, and Spotify or Apple Music. The full notch needs a Mac with a notch; other Macs get a pill at the top centre.

## Install

```bash
# Homebrew
brew install --cask frenkiieeee/mycss/mycss

# or one command
curl -fsSL https://raw.githubusercontent.com/frenkiieeee/MycSs/main/install.sh | bash
```

Or download the `.dmg` from [Releases](https://github.com/frenkiieeee/MycSs/releases), drag MycSs to Applications and, the first time, right click > Open (the app is not notarized). To build from source you only need the Xcode Command Line Tools: `./build-app.sh`.

After an update macOS may ask again for Accessibility and Full Disk Access.

## Permissions

| Permission | Used for | Required |
|---|---|---|
| Automation (Spotify, Music) | Reading the current song | Yes |
| Accessibility | Volume and brightness keys in the notch, and the keyboard light shortcut | No |
| Full Disk Access | Showing other apps' notifications in the notch | No |
| Calendars, Reminders | The calendar and reminders widgets | No |
| System audio | A visualiser that follows the real rhythm | No |

## Privacy

Everything runs on your Mac. Only the song title, artist and duration are sent, to LRCLIB, NetEase and QQ Music, to find the lyrics. The update check runs only when you press the button. No analytics, no accounts.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The technical notes are in [docs/architecture/internals.md](docs/architecture/internals.md) (Spanish).

## License

[MIT](LICENSE) © 2026 Frenkiieeee. The notch is inspired by boring.notch (GPL-3.0); no code was copied from it. Lyrics belong to their authors.
