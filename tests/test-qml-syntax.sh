#!/usr/bin/env bash
# Tests for QML file syntax validation
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

QML_FILES=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.qml" -type f)

echo "=== Test 1: QML files exist and are not empty ==="
if [ -z "$QML_FILES" ]; then
    fail "No .qml files found"
else
    for f in $QML_FILES; do
        name=$(basename "$f")
        if [ -s "$f" ]; then
            pass "$name exists and is not empty"
        else
            fail "$name is empty"
        fi
    done
fi

echo "=== Test 2: Required imports ==="
for f in $QML_FILES; do
    name=$(basename "$f")
    if grep -q "^import QtQuick" "$f"; then
        pass "$name imports QtQuick"
    else
        fail "$name missing 'import QtQuick'"
    fi
done

echo "=== Test 3: No hardcoded millisecond date arithmetic ==="
for f in $QML_FILES; do
    name=$(basename "$f")
    # 86400000 in date offset arithmetic (e.g. "new Date() - 86400000") is fragile.
    # Using it for duration formatting (remaining / 86400000) is acceptable.
    if grep "86400000" "$f" | grep -qvE '(remaining|elapsed|duration|diff)'; then
        fail "$name uses 86400000 outside duration formatting"
    else
        pass "$name no problematic 86400000 usage"
    fi
done

# The plugin renders whatever quota windows the proxy reports. A window id or a
# provider name written into the source is the bug this whole project exists to
# avoid: the day a provider ships a new window, or the user authorises a provider
# nobody thought of, a special case renders it wrong or drops it. Icon lookup is
# the one legitimate place a provider name may appear, so it is exempted by name.
echo "=== Test 4: No provider or quota-window id is special-cased ==="
BANNED='five-hour|seven-day|primary-window|thirty-day|claude|codex|anthropic|openai|copilot|gemini|kimi|xai'
for f in $QML_FILES $SCRIPT_DIR/get-quota; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if grep -inE "\"($BANNED)" "$f" | grep -viE '(icon|Icon)' | grep -q .; then
        grep -inE "\"($BANNED)" "$f" | grep -viE '(icon|Icon)' >&2
        fail "$name special-cases a provider or window id"
    else
        pass "$name treats providers and windows as data"
    fi
done

# remainingFraction is REMAINING, not used. Inverting it is a silent 100% error
# with no visible symptom, so the word `used` may not be attached to it.
echo "=== Test 5: remainingFraction is not treated as used ==="
for f in $QML_FILES; do
    name=$(basename "$f")
    if grep -inE 'used[A-Za-z]*[[:space:]]*[:=][^=]*remainingFraction' "$f" | grep -q .; then
        grep -inE 'used[A-Za-z]*[[:space:]]*[:=][^=]*remainingFraction' "$f" >&2
        fail "$name assigns remainingFraction to a 'used' value without inverting"
    else
        pass "$name keeps remaining and used distinct"
    fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
