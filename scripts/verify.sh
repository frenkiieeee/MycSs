#!/bin/bash
#
# One command that says whether a change broke something obvious.
#
#   ./scripts/verify.sh
#
# 1. swift build
# 2. the self test (parsers always; Spotify only if a track is playing)
# 3. (with --notch) the notch's own click test
# 4. every relative link in docs/, CLAUDE.md and README.md resolves
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
    echo ">> notch (real window, real clicks)"
    out=$(./.build/debug/MycSs --demo --notch-selftest /tmp/mycss-notch 2>&1)
    echo "$out" | grep -E "OK  |FAIL|passed|FAILED"
    if echo "$out" | grep -q "FAIL"; then fail=1; fi

    echo ">> settings previews (pictures, and the styles are undone)"
    out=$(./.build/debug/MycSs --demo --settings-snapshot /tmp/mycss-settings 2>&1)
    echo "$out" | grep "settings snapshot"
    if ! echo "$out" | grep -q "as they were"; then fail=1; fi
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
done < <(find docs -name '*.md'; echo CLAUDE.md; echo README.md)
if [ -s /tmp/mycss-verify-broken ]; then fail=1; fi
rm -f /tmp/mycss-verify-broken

if [ "$fail" -eq 0 ]; then
    echo "OK"
else
    echo "FAILED"
    exit 1
fi
