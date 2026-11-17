#!/bin/bash
#
# Removes MycSs and what it leaves behind.
#
#   ./scripts/uninstall.sh            asks first
#   ./scripts/uninstall.sh --yes      does not ask
#   ./scripts/uninstall.sh --prefix DIR   where the app is (default /Applications)
#   ./scripts/uninstall.sh --app-only     remove only the app, keep preferences, cache and logs
#
# Removes: the app, its preferences, its cache of lyrics and covers, its logs and
# the old login agent (if install-agent.sh was ever used). macOS keeps the
# permissions it granted; remove them in System Settings > Privacy & Security.
#
set -uo pipefail

PREFIX="/Applications"
YES=0
APP_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) YES=1; shift ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --app-only) APP_ONLY=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

APP="${PREFIX}/MycSs.app"
BUNDLE_ID="com.mycss.lyrics"
LIST=(
    "${APP}"
    "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
    "${HOME}/Library/Caches/MycSs"
    "${HOME}/Library/Logs/MycSs.log"
    "${HOME}/Library/Logs/MycSs.err.log"
    "${HOME}/Library/Logs/MycSs.out.log"
    "${HOME}/Library/LaunchAgents/${BUNDLE_ID}.plist"
)

if [ "${APP_ONLY}" -eq 1 ]; then
    LIST=("${APP}")
fi

echo "This will remove:"
for item in "${LIST[@]}"; do
    [ -e "${item}" ] && echo "  ${item}"
done

if [ "${YES}" -ne 1 ]; then
    printf "Continue? [y/N] "
    read -r answer
    case "${answer}" in y|Y|s|S) ;; *) echo "Cancelled."; exit 0 ;; esac
fi

if [ "${APP_ONLY}" -eq 0 ] && pgrep -x MycSs >/dev/null; then
    osascript -e 'tell application "MycSs" to quit' >/dev/null 2>&1 || pkill -x MycSs
    sleep 1
fi
[ "${APP_ONLY}" -eq 0 ] && launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" 2>/dev/null || true
# The preferences are cached by the system: delete through it, then the file.
[ "${APP_ONLY}" -eq 0 ] && defaults delete "${BUNDLE_ID}" 2>/dev/null || true

for item in "${LIST[@]}"; do
    rm -rf "${item}"
done
echo "MycSs removed."
