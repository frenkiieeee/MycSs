#!/bin/bash
#
# One command that says whether a change broke something obvious.
#
#   ./scripts/verify.sh
#
# 1. swift build
# 2. the self test (parsers always; Spotify only if a track is playing)
# 3. (with --notch) the notch's own click test
# 4. every relative link in docs/, CLAUDE.md and the READMEs resolves
# 5. VERSION is a semantic version, the shell scripts parse, and no long dash
#    (the project writes without it) is left in the code or the docs
#
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

echo ">> swift build"
if ! swift build 2>&1 | tail -3; then fail=1; fi
[ "${PIPESTATUS[0]}" -eq 0 ] || fail=1

echo ">> self test"
out=$(./.build/debug/MycSs --selftest 2>&1)
echo "$out" | grep -E "OK:|FAIL|error" | head -20
if echo "$out" | grep -qiE "FAIL"; then fail=1; fi

# The notch test opens the real notch window for a few seconds and clicks its
# controls, so it only runs when asked:  ./scripts/verify.sh --notch
if [ "${1:-}" = "--notch" ]; then
    # The real app has its own notch in the same place, and the test's clicks would land on it.
    if pgrep -x MycSs >/dev/null; then
        echo ">> MycSs is running: quit it first (its notch would take the test's clicks)"
        exit 1
    fi
    echo ">> notch (real window, real clicks)"
    out=$(./.build/debug/MycSs --demo --notch-selftest /tmp/mycss-notch 2>&1)
    echo "$out" | grep -E "OK  |FAIL|passed|FAILED"
    if echo "$out" | grep -q "FAIL"; then fail=1; fi

    echo ">> settings previews (pictures, and the styles are undone)"
    out=$(./.build/debug/MycSs --demo --settings-snapshot /tmp/mycss-settings 2>&1)
    echo "$out" | grep "settings snapshot"
    if ! echo "$out" | grep -q "as they were"; then fail=1; fi
    if echo "$out" | grep -q "!! FAILED"; then fail=1; fi
    for f in overlay-default notch-open notch-volume notch-notification; do
        [ -s "/tmp/mycss-settings-$f.png" ] || { echo "   missing /tmp/mycss-settings-$f.png"; fail=1; }
    done
fi

echo ">> docs links"
broken=0
while IFS= read -r file; do
    dir=$(dirname "$file")
    # [text](relative/path.md) and [text](relative/path.md#anchor), skipping URLs.
    grep -oE '\]\(([^)#]+)(#[^)]*)?\)' "$file" | sed -E 's/^\]\(([^)#]+).*/\1/' | while IFS= read -r link; do
        case "$link" in http*|mailto:*) continue ;; esac
        if [ ! -e "$dir/$link" ]; then
            echo "   broken link in $file: $link"
            echo 1 >> /tmp/mycss-verify-broken
        fi
    done
done < <(find docs -name '*.md'; echo CLAUDE.md; echo README.md; echo README.en.md; echo CONTRIBUTING.md; echo CHANGELOG.md)
if [ -s /tmp/mycss-verify-broken ]; then fail=1; fi
rm -f /tmp/mycss-verify-broken

echo ">> version, scripts and style"
EM=$(printf '\xe2\x80\x94')   # the characters are built here so this file does not contain them
EN=$(printf '\xe2\x80\x93')
if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$' VERSION; then echo "   VERSION is not x.y.z"; fail=1; fi
for script in build-app.sh install.sh scripts/*.sh; do
    bash -n "$script" || { echo "   syntax error in $script"; fail=1; }
done
if grep -rn --include='*.swift' --include='*.md' --include='*.sh' -e "$EM" -e "$EN" Sources docs README.md README.en.md CLAUDE.md CONTRIBUTING.md CHANGELOG.md scripts >/dev/null; then
    echo "   a long dash was found:"
    grep -rn --include='*.swift' --include='*.md' --include='*.sh' -e "$EM" -e "$EN" Sources docs README.md README.en.md CLAUDE.md CONTRIBUTING.md CHANGELOG.md scripts | head -5
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi
