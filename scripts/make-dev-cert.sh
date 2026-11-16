#!/bin/bash
#
# Makes a signing identity for MycSs builds, so macOS remembers the permissions it
# grants the app (Accessibility, for the volume and brightness keys; Calendar;
# Automation) from one build to the next.
#
# Without it the app is signed ad-hoc, and an ad-hoc signature is identified by
# the exact bytes of the binary: every build is a "different app" and every
# permission has to be given again. With this identity the signature is
# identified by the certificate instead (`identifier "com.mycss.lyrics" and
# certificate leaf = H"..."`), which does not change between builds.
#
#   ./scripts/make-dev-cert.sh      once
#   ./build-app.sh                  picks it up by itself
#
# **It touches nothing outside this folder.** The certificate lives in its own
# keychain file, `.dev-signing/dev.keychain-db`, which is not in your login
# keychain and not in any search list. It only signs local builds of this
# project. To undo it, delete the folder `.dev-signing` (and give the permissions
# once more).
#
set -euo pipefail
cd "$(dirname "$0")/.."

# An absolute path: `security create-keychain` puts a relative one in
# ~/Library/Keychains, which is exactly what this script must not do.
DIR="$(pwd)/.dev-signing"
KEYCHAIN="${DIR}/dev.keychain-db"
NAME="MycSs Dev"
# Not a secret: the key can only sign things for this project, on this Mac.
PASSWORD="mycss"

if [ -f "${KEYCHAIN}" ]; then
    echo "The signing identity already exists (${KEYCHAIN})."
    exit 0
fi

mkdir -p "${DIR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

cat > "${TMP}/cert.cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CFG

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" -config "${TMP}/cert.cfg" 2>/dev/null
# The classic encryption: the keychain cannot read what OpenSSL 3 uses by default.
openssl pkcs12 -export -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -out "${TMP}/cert.p12" -passout "pass:${PASSWORD}" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

security create-keychain -p "${PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings "${KEYCHAIN}"
security unlock-keychain -p "${PASSWORD}" "${KEYCHAIN}"
security import "${TMP}/cert.p12" -k "${KEYCHAIN}" -P "${PASSWORD}" -T /usr/bin/codesign >/dev/null
# Lets codesign use the key without asking.
security set-key-partition-list -S apple-tool:,apple: -s -k "${PASSWORD}" "${KEYCHAIN}" >/dev/null

echo "Done. The next ./build-app.sh signs with '${NAME}'."
echo "After the first build, give MycSs its permissions once more (Accessibility,"
echo "Calendars, Automation); they will stay."
