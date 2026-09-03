#!/usr/bin/env bash
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
    if grep "86400000" "$f" | grep -qvE '(remaining|elapsed|duration|diff)'; then
        fail "$name uses 86400000 outside duration formatting"
    else
        pass "$name no problematic 86400000 usage"
    fi
done

echo "=== Test 4: No provider, quota group, or model id is special-cased ==="
BANNED='five-hour|seven-day|primary-window|thirty-day|claude|codex|anthropic|openai|github|copilot|gemini|kimi|xai|fable|opus|sonnet|haiku|gpt|grok|deepseek|llama|mistral'
VERSION="[\"'][^\"'/]*(v[0-9]+|[0-9]+\.[0-9]+)"
for f in $QML_FILES $SCRIPT_DIR/get-quota; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if { grep -inE "($BANNED)" "$f"; grep -inE "$VERSION" "$f"; } | grep -vE '(iconAssets|icons\[|providerIcon)' | grep -q .; then
        { grep -inE "($BANNED)" "$f"; grep -inE "$VERSION" "$f"; } | grep -vE '(iconAssets|icons\[|providerIcon)' >&2
        fail "$name special-cases a provider, group, model, or version"
    else
        pass "$name treats providers, groups, and models as data"
    fi
done

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

echo "=== Test 6: carousel popout contract ==="
WIDGET="$SCRIPT_DIR/CliproxyQuotaWidget.qml"
if [ -e "$WIDGET" ]; then
    if grep -q "popoutContent:" "$WIDGET"; then
        pass "widget defines a popout"
    else
        fail "widget has no popoutContent"
    fi
    if grep -q "noQuota" "$WIDGET" && grep -q 'tr("no quota reported")' "$WIDGET"; then
        pass "groupless accounts render 'no quota reported', never a percent"
    else
        fail "widget does not handle noQuota accounts"
    fi
    if grep -q "savePluginData" "$WIDGET" && grep -q "focusedProvider" "$WIDGET"; then
        pass "focused provider is persisted via plugin settings"
    else
        fail "focused provider is not persisted"
    fi
else
    fail "CliproxyQuotaWidget.qml missing"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
