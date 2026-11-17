#!/bin/bash
#
# Builds the release app and packs it in a disk image for distribution.
#
#   ./scripts/make-dmg.sh
#
# Output (in dist/):  MycSs-<version>.dmg  and  MycSs-<version>.dmg.sha256
#
# The disk image holds MycSs.app, a shortcut to /Applications to drag it onto and
# a short LEEME with the first-open steps. It needs only what macOS ships (hdiutil).
#
# Not notarized: macOS asks for a right click > Open the first time. If a
# notarytool keychain profile is given in NOTARY_PROFILE, the image is notarized
# and stapled, which needs the app to be signed with a Developer ID.
#
set -eo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DIST="dist"
DMG="${DIST}/MycSs-${VERSION}.dmg"

./build-app.sh

STAGE="$(mktemp -d)/MycSs"
mkdir -p "${STAGE}"
cp -R MycSs.app "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
cat > "${STAGE}/LEEME.txt" <<TXT
MycSs ${VERSION}

1. Arrastra MycSs a Aplicaciones.
2. La primera vez: clic derecho sobre MycSs > Abrir > Abrir.
   (La app no esta notarizada por Apple, por eso macOS avisa.)
   Si macOS dice que esta danada: xattr -dr com.apple.quarantine /Applications/MycSs.app
3. Concede los permisos que pida (Automatizacion para leer Spotify o Musica;
   Accesibilidad para las teclas de volumen y brillo; Acceso total al disco
   solo si quieres ver las notificaciones en el notch).

https://github.com/frenkiieeee/MycSs
TXT

mkdir -p "${DIST}"
rm -f "${DMG}"
hdiutil create -volname "MycSs ${VERSION}" -srcfolder "${STAGE}" -ov -format UDZO "${DMG}" >/dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo ">> Notarizing with profile '${NOTARY_PROFILE}'..."
    xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG}"
fi

( cd "${DIST}" && shasum -a 256 "MycSs-${VERSION}.dmg" > "MycSs-${VERSION}.dmg.sha256" )

echo ">> ${DMG}"
echo ">> $(cut -d' ' -f1 "${DIST}/MycSs-${VERSION}.dmg.sha256")  (sha256)"
