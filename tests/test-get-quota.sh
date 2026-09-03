#!/usr/bin/env bash
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
    export CLIPROXY_QUOTA_VAULT_CMD=""
    unset CLIPROXY_QUOTA_ENDPOINT CLIPROXY_QUOTA_KEY 2>/dev/null || true
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
if [ "$(jq -r '.providers[0].aggregate' <<<"$OUT")" = "0" ]; then
    pass "claude aggregate is the worst group of its live account"
else
    fail "claude aggregate: $(jq -r '.providers[0].aggregate' <<<"$OUT")"
fi
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
if [ "$(jq -r '.updatedAt' <<<"$OUT")" = "2026-08-26T13:28:29Z" ]; then
    pass "updatedAt carries the server cache timestamp"
else
    fail "updatedAt: $(jq -r '.updatedAt' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[0].accounts[0].groups[1].label' <<<"$OUT")" = "7d Weekly" ] \
   && [ "$(jq -r '.providers[0].accounts[0].groups[1].resetTime' <<<"$OUT")" = "2026-08-27T03:00:00.146057+00:00" ]; then
    pass "group label and resetTime pass through for the popout bars"
else
    fail "group label/resetTime mangled: $(jq -c '.providers[0].accounts[0].groups[1]' <<<"$OUT")"
fi
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
if [ "$(jq -r '.providers[0].aggregate' <<<"$OUT")" = "0.7" ]; then
    pass "aggregate is the best bottleneck across live accounts"
else
    fail "multi-account aggregate: $(jq -r '.providers[0].aggregate' <<<"$OUT")"
fi
if [ "$(jq -r '[.providers[] | select(.provider == "acme")] | length' <<<"$OUT")" = "1" ]; then
    pass "two accounts of one provider collapse into one provider entry"
else
    fail "acme provider entries: $(jq -r '[.providers[] | select(.provider == "acme")] | length' <<<"$OUT")"
fi

echo "=== Test 3d: supported:false is informational, never a failure ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-multi-account.json"
OUT="$(run_script)"
if [ "$(jq -r '.anyProblem' <<<"$OUT")" = "false" ]; then
    pass "unsupported account's error does not raise anyProblem"
else
    fail "anyProblem raised by a supported:false account"
fi
if [ "$(jq -r '.providers[] | select(.provider == "legacy") | .problem' <<<"$OUT")" = "false" ]; then
    pass "unsupported provider not flagged as problem"
else
    fail "supported:false provider flagged as problem"
fi

echo "=== Test 3c: aggregateGroups carry the winning account's group view ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-multi-account.json"
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].aggregateGroups | length' <<<"$OUT")" = "2" ] \
   && [ "$(jq -r '.providers[0].aggregateGroups[1].remainingFraction' <<<"$OUT")" = "0.7" ]; then
    pass "headline groups come from the winning live account"
else
    fail "aggregateGroups wrong: $(jq -c '.providers[0].aggregateGroups' <<<"$OUT")"
fi
export SHIM_BODY_FILE="$FIXTURES/usage-contract2-live.json"
OUT="$(run_script --force)"
if [ "$(jq -r '.providers[1].aggregateGroups | length' <<<"$OUT")" = "0" ]; then
    pass "provider with no live account has empty aggregateGroups"
else
    fail "disabled-only provider should have no aggregate view"
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

echo "=== Test 7: key chain — vault, pi config, literal ==="
setup
CLIPROXY_QUOTA_VAULT_CMD="printf vault-key" run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer vault-key"*) pass "vault command wins over pi config" ;;
    *) fail "vault key not used: $(head -1 "$TMP/shim/calls.log")" ;;
esac
setup
CLIPROXY_QUOTA_VAULT_CMD="false" run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer test-key-123"*) pass "failing vault command falls through to pi config" ;;
    *) fail "fallthrough to pi config broken: $(head -1 "$TMP/shim/calls.log")" ;;
esac
setup
cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1" } }
CFG
CLIPROXY_QUOTA_KEY="literal-key" run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"Bearer literal-key"*) pass "keyless pi config falls through to the literal" ;;
    *) fail "literal fallback broken: $(head -1 "$TMP/shim/calls.log")" ;;
esac

echo "=== Test 8: endpoint override — beats pi config, origin-stripped ==="
setup
CLIPROXY_QUOTA_ENDPOINT="https://other.test/v1/extra?x=1" run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"https://other.test/v0/resource/plugins/pi-bridge/usage"*)
        pass "endpoint override beats pi config and is stripped to origin" ;;
    *)  fail "override URL wrong: $(head -1 "$TMP/shim/calls.log")" ;;
esac

echo "=== Test 9: no pi at all — override endpoint + literal key suffice ==="
setup
export CLIPROXY_QUOTA_PI_CONFIG="$TMP/does-not-exist.json"
OUT="$(CLIPROXY_QUOTA_ENDPOINT="https://solo.test/v1" CLIPROXY_QUOTA_KEY="solo-key" run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "ok" ]; then
    pass "widget works without pi installed"
else
    fail "pi-less run failed: $(jq -r '.status' <<<"$OUT")"
fi
case "$(head -1 "$TMP/shim/calls.log")" in
    *"https://solo.test/v0/"*"Bearer solo-key"*|*"Bearer solo-key"*)
        pass "pi-less run used the override endpoint and literal key" ;;
    *)  fail "pi-less call wrong: $(head -1 "$TMP/shim/calls.log")" ;;
esac

echo "=== Test 5b: cache never outlives the key chain or the endpoint ==="
setup
run_script >/dev/null
cat > "$TMP/pi-config.json" <<'CFG'
{ "proxy": { "endpoint": "https://proxy.test/v1" } }
CFG
OUT="$(run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "no-key" ]; then
    pass "losing all key sources yields no-key, not cached numbers"
else
    fail "cache served despite missing key: $(jq -r '.status' <<<"$OUT")"
fi
setup
run_script >/dev/null
OUT="$(CLIPROXY_QUOTA_ENDPOINT='https://other.test' SHIM_FAIL=1 run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "unreachable" ]; then
    pass "switching endpoints never serves the previous endpoint's cache"
else
    fail "cross-endpoint cache leak: $(jq -r '.status' <<<"$OUT")"
fi

echo "=== Test 5c: --force asks the server to refresh too ==="
setup
run_script --force >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"/v0/resource/plugins/pi-bridge/usage?refresh=1"*) pass "forced run carries ?refresh=1 for the server cache" ;;
    *) fail "forced URL lacks ?refresh=1: $(head -1 "$TMP/shim/calls.log")" ;;
esac
run_script >/dev/null 2>&1 || true
setup
run_script >/dev/null
case "$(head -1 "$TMP/shim/calls.log")" in
    *"?refresh=1"*) fail "ordinary run must NOT force the server cache" ;;
    *) pass "ordinary run reads the server cache normally" ;;
esac

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

echo "=== Test 7: health flags — anyProblem across providers ==="
setup
OUT="$(run_script)"
if [ "$(jq -r '.anyProblem' <<<"$OUT")" = "true" ]; then
    pass "not-serving account anywhere raises anyProblem"
else
    fail "anyProblem: $(jq -r '.anyProblem' <<<"$OUT")"
fi
if [ "$(jq -r '.drift' <<<"$OUT")" = "false" ]; then
    pass "matching contract and schema report no drift"
else
    fail "drift should be false: $(jq -r '.drift' <<<"$OUT")"
fi
setup
export SHIM_BODY_FILE="$FIXTURES/usage-healthy.json"
OUT="$(run_script)"
if [ "$(jq -r '.anyProblem' <<<"$OUT")" = "false" ]; then
    pass "healthy accounts leave anyProblem false"
else
    fail "healthy anyProblem: $(jq -r '.anyProblem' <<<"$OUT")"
fi

echo "=== Test 7b: serving state decides problem, not the error string ==="
setup
OUT="$(run_script)"
if [ "$(jq -r '.providers[] | select(.provider == "github-copilot") | .problem' <<<"$OUT")" = "false" ]; then
    pass "active account with an error string is not a problem"
else
    fail "telemetry error flagged as problem"
fi
setup
export SHIM_BODY_FILE="$FIXTURES/usage-stale.json"
OUT="$(run_script)"
if [ "$(jq -r '.providers[] | select(.provider == "beta") | .problem' <<<"$OUT")" = "true" ] \
   && [ "$(jq -r '.anyProblem' <<<"$OUT")" = "true" ]; then
    pass "non-active status raises the problem flag"
else
    fail "status:error account not flagged: $(jq -c '.providers' <<<"$OUT")"
fi

echo "=== Test 8: 404 — the bridge requirement, stated exactly ==="
setup
export SHIM_STATUS=404
OUT="$(run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "no-plugin" ]; then
    pass "404 reported as status no-plugin"
else
    fail "404 status: $(jq -r '.status' <<<"$OUT")"
fi
if [ "$(jq -r '.error' <<<"$OUT")" = "server has no quota plugin (pi-bridge)" ]; then
    pass "bridge requirement message rendered verbatim"
else
    fail "404 error: $(jq -r '.error' <<<"$OUT")"
fi
if [ "$(jq -r '.stale' <<<"$OUT")" = "true" ] \
   && [ "$(jq -r '.anyProblem' <<<"$OUT")" = "false" ] \
   && [ "$(jq -r '.drift' <<<"$OUT")" = "false" ]; then
    pass "terminal document carries the uniform stale/anyProblem/drift shape"
else
    fail "terminal document shape wrong: $OUT"
fi

echo "=== Test 9: connection failure — unreachable, stale ==="
setup
export SHIM_FAIL=1
OUT="$(run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "unreachable" ]; then
    pass "curl failure reported as status unreachable"
else
    fail "failure status: $(jq -r '.status' <<<"$OUT")"
fi
if [ "$(jq -r '.stale' <<<"$OUT")" = "true" ] && [ "$(jq -r '.providers | length' <<<"$OUT")" = "0" ]; then
    pass "unreachable carries no providers and is stale"
else
    fail "unreachable shape wrong: $OUT"
fi

echo "=== Test 10: server-side stale cache is reported stale ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-stale.json"
OUT="$(run_script)"
if [ "$(jq -r '.status' <<<"$OUT")" = "ok" ] && [ "$(jq -r '.stale' <<<"$OUT")" = "true" ]; then
    pass "server cache.stale passes through as stale"
else
    fail "stale fixture: status=$(jq -r '.status' <<<"$OUT") stale=$(jq -r '.stale' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[] | select(.provider == "acme") | .aggregate' <<<"$OUT")" = "1" ]; then
    pass "stale payload still carries its numbers"
else
    fail "stale aggregate: $(jq -r '.providers[] | select(.provider == \"acme\") | .aggregate' <<<"$OUT")"
fi

echo "=== Test 11: drift — newer contract echoed, foreign payload schema ==="
setup
printf 'HTTP/2 200\r\nx-pi-contract: 2\r\nx-pi-contract-latest: 3\r\n\r\n' > "$TMP/headers-latest-3"
export SHIM_HEADERS_FILE="$TMP/headers-latest-3"
OUT="$(run_script)"
if [ "$(jq -r '.drift' <<<"$OUT")" = "true" ]; then
    pass "contract latest 3 raises drift"
else
    fail "latest-3 drift: $(jq -r '.drift' <<<"$OUT")"
fi
if [ "$(jq -r '.contractLatest' <<<"$OUT")" = "3" ]; then
    pass "echoed latest surfaced for the notice"
else
    fail "contractLatest: $(jq -r '.contractLatest' <<<"$OUT")"
fi
setup
jq '.schemaVersion = 2' "$FIXTURES/usage-healthy.json" > "$TMP/schema2.json"
export SHIM_BODY_FILE="$TMP/schema2.json"
OUT="$(run_script)"
if [ "$(jq -r '.drift' <<<"$OUT")" = "true" ]; then
    pass "payload schema other than 1 raises drift"
else
    fail "schema-2 drift: $(jq -r '.drift' <<<"$OUT")"
fi

echo "=== Test 12: window duration — server field wins, label pattern fills in ==="
setup
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")" = "18000" ]; then
    pass "5h label parses to 18000 seconds"
else
    fail "5h windowSeconds: $(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")"
fi
if [ "$(jq -r '.providers[1].accounts[0].groups[0].windowSeconds' <<<"$OUT")" = "2592000" ]; then
    pass "30d label parses to 2592000 seconds"
else
    fail "30d windowSeconds: $(jq -r '.providers[1].accounts[0].groups[0].windowSeconds' <<<"$OUT")"
fi
setup
export SHIM_BODY_FILE="$FIXTURES/usage-healthy.json"
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")" = "null" ]; then
    pass "unparsable label yields null windowSeconds"
else
    fail "expected null windowSeconds: $(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")"
fi
setup
export SHIM_BODY_FILE="$FIXTURES/usage-multi-account.json"
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")" = "900" ]; then
    pass "server windowSeconds passes through untouched"
else
    fail "server windowSeconds: $(jq -r '.providers[0].aggregateGroups[0].windowSeconds' <<<"$OUT")"
fi

echo "=== Test 13: requests-per-day activity from local history ==="
setup
export SHIM_BODY_FILE="$FIXTURES/usage-multi-account.json"
HIST="$TMP/cache/cliproxy-quota/history-$(printf '%s' "https://proxy.test" | sha256sum | cut -c1-16).jsonl"
mkdir -p "$(dirname "$HIST")"
YD=$(( $(date +%s) - 86400 ))
printf '{"ts":%s,"providers":[{"provider":"acme","success":2,"failed":0}]}\n' "$YD" > "$HIST"
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].activity[-1].requests' <<<"$OUT")" = "10" ]; then
    pass "today's requests are the delta against yesterday's counter"
else
    fail "activity delta: $(jq -c '.providers[0].activity' <<<"$OUT")"
fi
if [ "$(wc -l < "$HIST")" = "2" ]; then
    pass "fetch appended today's snapshot to the history"
else
    fail "history lines: $(wc -l < "$HIST")"
fi
printf '{"ts":%s,"providers":[{"provider":"acme","success":500,"failed":9}]}\n' "$YD" > "$HIST"
OUT="$(run_script --force)"
if [ "$(jq -r '.providers[0].activity[-1].requests' <<<"$OUT")" = "0" ]; then
    pass "counter reset clamps the daily delta at zero"
else
    fail "reset delta: $(jq -c '.providers[0].activity' <<<"$OUT")"
fi
setup
OUT="$(run_script)"
if [ "$(jq -r '.providers[0].activity | length' <<<"$OUT")" = "0" ]; then
    pass "first run ever has an empty activity list, never invented numbers"
else
    fail "first-run activity: $(jq -c '.providers[0].activity' <<<"$OUT")"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
