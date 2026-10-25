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
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Agent app: lives in the menu bar, no Dock icon. -->
    <key>LSUIElement</key><true/>
    <!-- Required for the Apple Event that reads the current track from Spotify. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>MycSs reads the current song and playback position from Spotify so it can show the lyrics in sync on the lock screen.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo ">> Ad-hoc signing..."
codesign --force --deep --sign - "${APP}"

echo ">> Built $(pwd)/${APP}"
echo
echo "   Run it:  open ${APP}"
echo "   Test it: Cmd+L to lock the screen, then look for the red overlay."
echo "   Logs:    tail -f ~/Library/Logs/MycSs.log"
