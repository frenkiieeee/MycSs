#!/bin/bash
#
# Builds MycSs and assembles a runnable .app bundle.
#
# macOS: this project is built with SwiftPM + the Command Line Tools only, no
# Xcode required. `swift build` produces the binary; this script wraps it in a
# bundle with the Info.plist the app needs and ad-hoc signs it so macOS will
# launch it.
#
# Usage:
#   ./build-app.sh          release build (default)
#   ./build-app.sh debug    debug build
#
set -eo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="MycSs.app"
CONTENTS="${APP}/Contents"
BUNDLE_ID="com.mycss.lyrics"

if [ "$CONFIG" = "debug" ]; then
    echo ">> Building debug binary..."
    swift build
    BUILT=".build/debug/MycSs"
else
    echo ">> Building release binary..."
    swift build -c release
    BUILT=".build/release/MycSs"
fi

if [ ! -f "${BUILT}" ]; then
    echo "ERROR: expected binary at ${BUILT}" >&2
    exit 1
fi

echo ">> Assembling ${APP} ..."
rm -rf "${APP}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "${BUILT}" "${CONTENTS}/MacOS/MycSs"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MycSs</string>
    <key>CFBundleDisplayName</key><string>MycSs</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>MycSs</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Agent app: lives in the menu bar, no Dock icon. -->
    <key>LSUIElement</key><true/>
    <!-- Required for the Apple Events that read the current track from Spotify and Music. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>MycSs reads the current song and playback position from Spotify and Apple Music so it can show the lyrics in sync.</string>
    <!-- The calendar tab of the notch. The permission is only asked when it is opened. -->
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>MycSs shows your next events in the notch. It only reads them on your Mac.</string>
    <!-- The notch's visualiser, when the user turns on "follow the real rhythm". -->
    <key>NSAudioCaptureUsageDescription</key>
    <string>MycSs listens to the sound your Mac is playing only to make the notch bars follow the rhythm. Nothing is recorded or sent anywhere.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>MycSs shows your next events in the notch. It only reads them on your Mac.</string>
    <!-- The reminders widget of the notch. -->
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>MycSs shows your pending reminders in the notch and lets you tick them off. It only reads them on your Mac.</string>
    <key>NSRemindersUsageDescription</key>
    <string>MycSs shows your pending reminders in the notch and lets you tick them off. It only reads them on your Mac.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${CONTENTS}/PkgInfo"

# Mascot: a subset of the PNG set goes into the bundle, plus the app icon and the
# menu bar icon. Assets/Mascot is the source of truth (see docs/brand).
MASCOT="Assets/Mascot/png"
mkdir -p "${CONTENTS}/Resources/Mascot"
for name in neutro feliz durmiendo pensando curioso state-auriculares; do
    cp "${MASCOT}/mycss-${name}-512.png" "${CONTENTS}/Resources/Mascot/"
done
# The menu bar icon is a template image (black on transparent), drawn at 18 pt.
# Both icons come from Assets/Mascot/appicon/generate.py and are committed.
ICONS="Assets/Mascot/appicon"
cp "${ICONS}/MenuIcon.png" "${CONTENTS}/Resources/MenuIcon.png"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
    sips -z ${size} ${size} "${ICONS}/AppIcon-1024.png" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "${ICONS}/AppIcon-1024.png" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${CONTENTS}/Resources/AppIcon.icns"

# Signing. With `.dev-signing/` (made by scripts/make-dev-cert.sh) the app is
# signed with a stable identity, so macOS keeps the permissions it grants (the
# Accessibility one for the volume keys) between builds. Without it the app is
# signed ad-hoc, which is a different identity every build. CODESIGN_IDENTITY
# overrides both.
DEV_KEYCHAIN="$(pwd)/.dev-signing/dev.keychain-db"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo ">> Signing with '${CODESIGN_IDENTITY}'..."
    codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP}"
elif [ -f "${DEV_KEYCHAIN}" ]; then
    echo ">> Signing with 'MycSs Dev' (stable identity)..."
    security unlock-keychain -p mycss "${DEV_KEYCHAIN}"
    codesign --force --deep --sign "MycSs Dev" --keychain "${DEV_KEYCHAIN}" "${APP}"
else
    echo ">> Ad-hoc signing (run scripts/make-dev-cert.sh for a stable signature)..."
    codesign --force --deep --sign - "${APP}"
fi

echo ">> Built $(pwd)/${APP}"
echo
echo "   Run it:  open ${APP}"
echo "   Test it: Cmd+L to lock the screen, then look for the red overlay."
echo "   Logs:    tail -f ~/Library/Logs/MycSs.log"
