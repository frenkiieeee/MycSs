#!/bin/bash
#
# Prepares a release: checks, version, disk image, checksum and the cask.
#
#   ./scripts/release.sh 0.3.0            # a new version
#   ./scripts/release.sh                  # the version already in VERSION
#   ./scripts/release.sh 0.3.0 --allow-dirty
#
# It never runs git for you: it prints the tag and push commands at the end,
# because commits and pushes are made by hand in this project.
#
set -eo pipefail
cd "$(dirname "$0")/.."

NEW=""
DIRTY=0
for arg in "$@"; do
    case "$arg" in
        --allow-dirty) DIRTY=1 ;;
        *) NEW="$arg" ;;
    esac
done

if [ -n "${NEW}" ]; then
    if ! echo "${NEW}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
        echo "ERROR: '${NEW}' is not a semantic version (x.y.z)" >&2
        exit 1
    fi
    CURRENT="$(tr -d '[:space:]' < VERSION)"
    if [ "${NEW}" != "${CURRENT}" ] && [ "$(printf '%s\n%s\n' "${CURRENT%%-*}" "${NEW%%-*}" | sort -V | tail -1)" != "${NEW%%-*}" ]; then
        echo "ERROR: ${NEW} is lower than the current ${CURRENT}" >&2
        exit 1
    fi
fi

if [ "${DIRTY}" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: there are uncommitted changes. Commit them first, or pass --allow-dirty." >&2
    exit 1
fi

if [ -n "${NEW}" ]; then
    echo "${NEW}" > VERSION
fi
VERSION="$(tr -d '[:space:]' < VERSION)"

if ! grep -q "^## \[${VERSION}\]" CHANGELOG.md; then
    echo "ERROR: CHANGELOG.md has no '## [${VERSION}]' section. Write it first." >&2
    exit 1
fi

echo ">> Checks"
./scripts/verify.sh --notch

echo ">> Disk image"
./scripts/make-dmg.sh

SHA="$(cut -d' ' -f1 "dist/MycSs-${VERSION}.dmg.sha256")"

echo ">> Homebrew cask"
CASK="packaging/homebrew/mycss.rb"
sed -i '' -E "s/^  version \".*\"/  version \"${VERSION}\"/; s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" "${CASK}"

cat <<DONE

== MycSs ${VERSION} is ready ==
   dist/MycSs-${VERSION}.dmg
   sha256 ${SHA}

Next, by hand:
   git add VERSION CHANGELOG.md packaging/homebrew/mycss.rb
   git commit -m "chore(release): ${VERSION}"
   git tag -a v${VERSION} -m "MycSs ${VERSION}"
   git push origin main --tags
Then publish dist/MycSs-${VERSION}.dmg (and its .sha256) as a GitHub release for
the tag, and copy ${CASK} to the tap (frenkiieeee/homebrew-mycss, Casks/mycss.rb).
DONE
