#!/bin/bash
#
# Installs MycSs.
#
#   curl -fsSL https://raw.githubusercontent.com/frenkiieeee/MycSs/main/install.sh | bash
#
# Options (after `bash -s --` when piping):
#   --version X.Y.Z   a specific version (default: the latest release)
#   --prefix DIR      where to put MycSs.app (default: /Applications)
#   --from-source     build it with SwiftPM instead of downloading the image
#   --source-dir DIR  with --from-source, build this checkout instead of cloning
#   --no-open         do not open the app at the end
#
# It downloads the disk image from GitHub Releases, checks its sha256, copies the
# app, and removes the quarantine flag macOS puts on downloads (the app is not
# notarized, so it would otherwise need a right click > Open).
#
set -eo pipefail

REPO="frenkiieeee/MycSs"
PREFIX="/Applications"
VERSION=""
FROM_SOURCE=0
SOURCE_DIR=""
OPEN=1

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --from-source) FROM_SOURCE=1; shift ;;
        --source-dir) SOURCE_DIR="$2"; FROM_SOURCE=1; shift 2 ;;
        --no-open) OPEN=0; shift ;;
        -h|--help) sed -n '3,18p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ "$(uname -s)" != "Darwin" ]; then
    echo "MycSs is a macOS app." >&2
    exit 1
fi
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "${MAJOR}" -lt 15 ]; then
    echo "MycSs needs macOS 15 or later (this Mac has $(sw_vers -productVersion))." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'hdiutil detach "${WORK}/mnt" -quiet 2>/dev/null || true; rm -rf "${WORK}"' EXIT

mkdir -p "${PREFIX}"

if [ "${FROM_SOURCE}" -eq 1 ]; then
    command -v swift >/dev/null || { echo "Swift is needed: xcode-select --install" >&2; exit 1; }
    if [ -n "${SOURCE_DIR}" ]; then
        SRC="${SOURCE_DIR}"
    else
        echo ">> Downloading the source..."
        git clone --depth 1 "https://github.com/${REPO}.git" "${WORK}/src" >/dev/null 2>&1
        SRC="${WORK}/src"
    fi
    ( cd "${SRC}" && ./build-app.sh )
    APP_SRC="${SRC}/MycSs.app"
else
    if [ -z "${VERSION}" ]; then
        echo ">> Looking for the latest release..."
        VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
            | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
        [ -n "${VERSION}" ] || { echo "No release found. Try --from-source." >&2; exit 1; }
    fi
    BASE="https://github.com/${REPO}/releases/download/v${VERSION}"
    echo ">> Downloading MycSs ${VERSION}..."
    curl -fL --progress-bar -o "${WORK}/MycSs.dmg" "${BASE}/MycSs-${VERSION}.dmg"
    curl -fsSL -o "${WORK}/MycSs.dmg.sha256" "${BASE}/MycSs-${VERSION}.dmg.sha256"

    EXPECTED="$(cut -d' ' -f1 "${WORK}/MycSs.dmg.sha256")"
    ACTUAL="$(shasum -a 256 "${WORK}/MycSs.dmg" | cut -d' ' -f1)"
    if [ "${EXPECTED}" != "${ACTUAL}" ]; then
        echo "ERROR: the download does not match its checksum." >&2
        exit 1
    fi
    echo ">> Checksum OK"

    mkdir -p "${WORK}/mnt"
    hdiutil attach "${WORK}/MycSs.dmg" -nobrowse -quiet -mountpoint "${WORK}/mnt"
    APP_SRC="${WORK}/mnt/MycSs.app"
fi

if pgrep -x MycSs >/dev/null; then
    echo ">> Closing the running MycSs..."
    osascript -e 'tell application "MycSs" to quit' >/dev/null 2>&1 || pkill -x MycSs || true
    sleep 1
fi

echo ">> Installing in ${PREFIX}..."
rm -rf "${PREFIX}/MycSs.app"
ditto "${APP_SRC}" "${PREFIX}/MycSs.app"

echo ">> Removing the download quarantine flag (the app is not notarized)."
xattr -dr com.apple.quarantine "${PREFIX}/MycSs.app" 2>/dev/null || true

echo
echo "MycSs is installed: ${PREFIX}/MycSs.app"
echo "The first time, macOS asks for permissions (Automation to read Spotify or Music)."
echo "After an update, grant Accessibility and Full Disk Access again if you used them."
[ "${OPEN}" -eq 1 ] && open "${PREFIX}/MycSs.app"
exit 0
