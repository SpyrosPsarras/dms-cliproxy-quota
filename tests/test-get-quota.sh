#!/usr/bin/env bash
# Tests for get-quota, entirely through its stdout — the project's single seam.
# HTTP is faked by tests/shim/curl on PATH; config comes from a temp pi config.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GET_QUOTA="$SCRIPT_DIR/get-quota"
FIXTURES="$SCRIPT_DIR/tests/fixtures"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fresh shim + config + cache environment for every run.
setup() {
    rm -rf "$TMP/shim" "$TMP/cache"
    mkdir -p "$TMP/shim" "$TMP/cache"
    export SHIM_DIR="$TMP/shim"
    export SHIM_BODY_FILE="$FIXTURES/usage-contract2-live.json"
    unset SHIM_STATUS SHIM_FAIL SHIM_HEADERS_FILE 2>/dev/null || true
    cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1", "apiKey": "test-key-123" } }
CFG
    export CLIPROXY_QUOTA_PI_CONFIG="$TMP/pi-config.json"
    export XDG_CACHE_HOME="$TMP/cache"
}

run_script() {
    PATH="$SCRIPT_DIR/tests/shim:$PATH" bash "$GET_QUOTA" "$@"
}

echo "=== Test 1: normalizes the live fixture ==="
setup
OUT="$(run_script)"
if jq -e '.status == "ok"' <<<"$OUT" >/dev/null; then
    pass "status is ok"
else
    fail "status is not ok: $(jq -r '.status // "missing"' <<<"$OUT" 2>/dev/null)"
fi
if [ "$(jq -r '.providers | length' <<<"$OUT")" = "3" ]; then
    pass "three providers, server order preserved"
else
    fail "expected 3 providers, got $(jq -r '.providers | length' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[0].provider' <<<"$OUT")" = "claude" ]; then
    pass "first provider is claude (server order)"
else
    fail "first provider is $(jq -r '.providers[0].provider' <<<"$OUT")"
fi
# claude's single live account bottoms out at 0 (worst group wins within an account)
if [ "$(jq -r '.providers[0].aggregate' <<<"$OUT")" = "0" ]; then
    pass "claude aggregate is the worst group of its live account"
else
    fail "claude aggregate: $(jq -r '.providers[0].aggregate' <<<"$OUT")"
fi
# codex's only account is disabled: no live account, no aggregate
if [ "$(jq -r '.providers[1].aggregate' <<<"$OUT")" = "null" ]; then
    pass "disabled codex account is excluded from the aggregate"
else
    fail "codex aggregate should be null, got $(jq -r '.providers[1].aggregate' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[1].accounts[0].disabled' <<<"$OUT")" = "true" ]; then
    pass "disabled account still listed, labelled disabled"
else
    fail "disabled account missing from output"
fi
# copilot reports no groups: noQuota, never 0%
if [ "$(jq -r '.providers[2].accounts[0].noQuota' <<<"$OUT")" = "true" ]; then
    pass "groupless account flagged noQuota"
else
    fail "groupless account not flagged noQuota"
fi
if [ "$(jq -r '.providers[2].aggregate' <<<"$OUT")" = "null" ]; then
    pass "groupless account never renders as 0%"
else
    fail "groupless copilot aggregate should be null"
fi

echo "=== Test 2: transport — origin strip, auth, contract pin ==="
setup
run_script >/dev/null
CALL="$(head -1 "$TMP/shim/calls.log")"
case "$CALL" in
    *"https://proxy.test/v0/resource/plugins/pi-bridge/usage"*)
        pass "endpoint stripped to origin, bridge route appended" ;;
    *)  fail "URL wrong: $CALL" ;;
esac
case "$CALL" in
    *"Authorization: Bearer test-key-123"*) pass "ordinary key sent as Bearer" ;;
    *) fail "Authorization header missing" ;;
esac
case "$CALL" in
    *"X-Pi-Contract: 2"*) pass "contract version 2 pinned" ;;
    *) fail "X-Pi-Contract header missing" ;;
esac

echo "=== Test 3: remainingFraction is remaining — full stays full ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-healthy.json"
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].aggregate' <<<"$OUT")" = "1" ]; then
    pass "aggregate 1 survives normalization (never inverted to used)"
else
    fail "healthy aggregate: $(jq -r '.providers[0].aggregate' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[0].accounts[0].groups[0].remainingFraction' <<<"$OUT")" = "1" ]; then
    pass "group fraction passed through as remaining"
else
    fail "group fraction mangled"
fi

echo "=== Test 3b: best live account wins across accounts ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-multi-account.json"
OUT="$(run_script)"
# account bottlenecks: 0.2 and 0.7 — the router picks the account with headroom
if [ "$(jq -r '.providers[0].aggregate' <<<"$OUT")" = "0.7" ]; then
    pass "aggregate is the best bottleneck across live accounts"
else
    fail "multi-account aggregate: $(jq -r '.providers[0].aggregate' <<<"$OUT")"
fi
if [ "$(jq -r '.providers | length' <<<"$OUT")" = "1" ]; then
    pass "two accounts of one provider collapse into one provider entry"
else
    fail "provider count: $(jq -r '.providers | length' <<<"$OUT")"
fi

echo "=== Test 4: key resolution — !command form ==="
setup
cat > "$TMP/pi-config.json" <<CFG
{ "proxy": { "endpoint": "https://proxy.test/v1", "apiKey": "!printf cmd-resolved-key" } }
CFG
run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer cmd-resolved-key"*) pass "!command key resolved at fetch time" ;;
    *) fail "!command key not resolved" ;;
esac

echo "=== Test 4b: key resolution — \$ENV form and whitespace trim ==="
setup
cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1", "apiKey": "$TEST_QUOTA_KEY" } }
CFG
TEST_QUOTA_KEY="env-resolved-key" run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer env-resolved-key"*) pass "\$ENV key resolved from the environment" ;;
    *) fail "\$ENV key not resolved" ;;
esac
setup
cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1", "apiKey": "  padded-key  " } }
CFG
run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer padded-key"*) pass "literal key trimmed like pi's resolveConfigValue" ;;
    *) fail "padded literal not trimmed" ;;
esac

echo "=== Test 5: local cache — TTL respected, --force bypasses ==="
setup
run_script >/dev/null
run_script >/dev/null
if [ "$(wc -l < "$TMP/shim/calls.log")" = "1" ]; then
    pass "second run within TTL served from local cache"
else
    fail "cache miss: $(wc -l < "$TMP/shim/calls.log") HTTP calls"
fi
run_script --force >/dev/null
if [ "$(wc -l < "$TMP/shim/calls.log")" = "2" ]; then
    pass "--force bypasses the local cache"
else
    fail "--force did not refetch"
fi

echo "=== Test 6: no key anywhere — states it, exits cleanly ==="
setup
cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1" } }
CFG
OUT="$(run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "no-key" ]; then
    pass "missing key reported as status no-key"
else
    fail "status: $(jq -r '.status' <<<"$OUT" 2>/dev/null)"
fi
if [ ! -s "$TMP/shim/calls.log" ] 2>/dev/null || [ ! -e "$TMP/shim/calls.log" ]; then
    pass "no HTTP call attempted without a key"
else
    fail "HTTP call made despite missing key"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
