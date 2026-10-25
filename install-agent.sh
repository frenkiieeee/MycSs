#!/bin/bash
#
# Installs (or removes) MycSs as a login agent, so it starts automatically when
# the Mac boots.
#
# The agent is installed on request only: the app never writes it without the
# user asking. Run this script directly, or use the menu item.
#
# Usage:
#   ./install-agent.sh            install
#   ./install-agent.sh --remove   uninstall
#
set -eo pipefail
cd "$(dirname "$0")"

PLIST="$HOME/Library/LaunchAgents/com.mycss.lyrics.plist"
LABEL="com.mycss.lyrics"
APP="$(pwd)/MycSs.app"

if [ ! -d "${APP}" ]; then
    echo "ERROR: ${APP} not found. Run ./build-app.sh first." >&2
    exit 1
fi

if [ "$1" = "--remove" ]; then
    if [ -f "${PLIST}" ]; then
        launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
        rm -f "${PLIST}"
        echo ">> Removed ${PLIST}"
    else
        echo ">> Not installed."
    fi
    exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP}/Contents/MacOS/MycSs</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>StandardErrorPath</key><string>${HOME}/Library/Logs/MycSs.err.log</string>
    <key>StandardOutPath</key><string>${HOME}/Library/Logs/MycSs.out.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST}"

echo ">> Installed ${PLIST}"
echo ">> MycSs will start automatically at login."
echo ">> Uninstall with: ./install-agent.sh --remove"
