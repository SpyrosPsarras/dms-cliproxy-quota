# Per-account usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show which account used which part of every Daily Activity and Models bar, with account filter chips, for providers with 2+ accounts.

**Architecture:** The bridge keeps cumulative token counters per account and attaches them to each account on every v2 serve. `get-quota` stores them in its history and turns them into per-day, per-account deltas next to the existing provider totals. The widget adds a view layer (selected account, account colours, filtered activity) over the unchanged `All` data and draws outlined boxes over the existing model-coloured bars.

**Tech Stack:** Go 1.26 (bridge, CLIProxyAPI SDK v7.2.93), bash + jq (`get-quota`), QML/Quickshell (DankMaterialShell widget), node `vm` tests for widget logic.

**Spec:** `docs/superpowers/specs/2026-11-19-per-account-usage-design.md`

## Global Constraints

- Key all per-account data by `authIndex`, never by the masked `account` name.
- Bridge contract v1 output stays byte-identical; per-account `tokens` only in contract v2.
- The document-level `models` array keeps its current shape.
- Single-account providers: no account colour, no outlines, no chips; PR #32 accent border and error border stay.
- Model-family colours and the Daily Activity bar scale always come from the `All` data, also under a chip.
- Every non-zero account box is at least 3 px tall (daily) or wide (models).
- New UI strings go through `root.tr()` with `fr` and `es` entries in `translations.js`.
- No hardcoded provider, model or group names (`tests/test-qml-syntax.sh`). No code comments beyond a one-line why.
- Bridge: `gofmt` clean; bump `pluginVersion` in `main.go` from `0.11.0` to `0.12.0`.

## Review Focus

1. Account boxes that add up to more than the bar (provider and account deltas taken from slightly different snapshots): boxes are clamped so their stack never exceeds the bar. Test in Task 3 (`clampedBoxes`).
2. Old bridge or history from before the change (no `accounts` in snapshots): no chips, no outlines, totals unchanged. Tests in Task 2 and Task 3.
3. The selected chip's account disappears after a refresh: the view falls back to `All`. Test in Task 3.
4. Bridge restart (account counters drop): per-account delta uses the existing `delta()` rule, never negative. Test in Task 2.
5. A day where only some accounts have data, or an `authIndex` no longer listed: its tokens stay un-outlined, and listed accounts' boxes are sized against the full bar. Test in Task 3.

---

### Task 1: Bridge per-account token counters

Repo: `SpyrosPsarras/pi-cliproxyapi-bridge`, checkout at `~/src/pi-cliproxyapi-bridge`, branch `t3/per-account-tokens` from `origin/main`.

**Files:**
- Modify: `tokenstats.go` (new counters + snapshot)
- Modify: `main.go:493-515` (`shapeForContract`, attach per account) and `pluginVersion`
- Modify: `quota.go:39-53` (`usageAccount` gains `Tokens map[string]int64 \`json:"tokens,omitempty"\``)
- Test: `tokenstats_test.go`

**Interfaces:**
- Produces: `func recordTokenUsage(rec usageRecord)` also adds `rec`'s total to a per-`AuthIndex` per-model counter (skip when `AuthIndex` is empty); `func accountTokenSnapshot(authIndex string) map[string]int64` returns model id → cumulative total, nil when none. JSON: each v2 account carries `"tokens": {"<model id>": <total>}`.

- [ ] **Step 1: Write failing tests** in `tokenstats_test.go`:
  - `TestRecordTokenUsageAccumulatesPerAccount`: two records for `AuthIndex` `"a1"` (`claude-opus-5`, totals 100 and 50) and one for `"b2"` (`claude-opus-5`, 30) → `accountTokenSnapshot("a1")["claude-opus-5"] == 150`, `accountTokenSnapshot("b2")["claude-opus-5"] == 30`, `accountTokenSnapshot("zz") == nil`.
  - `TestRecordTokenUsageAccountUsesSameTotalRule`: record with no `TotalTokens`, input 10 output 5 → account total 15.
  - `TestShapeForContractAttachesAccountTokensOnlyForV2`: cached doc with accounts `a1`, `b2`, `c3` (`c3` never used); v1 output byte-equal to cached; v2 output has `a1.tokens["claude-opus-5"] == 150`, `c3` has no `tokens` key.
  - Extend `resetTokenStats()` to clear the per-account map.
- [ ] **Step 2: Run** `go test ./...` (see "Running Go" below). Expected: the three new tests fail to compile or fail.
- [ ] **Step 3: Implement** the counters under the existing `tokenStatsMu`, `accountTokenSnapshot` returning a copy, and in `shapeForContract` v2 branch loop `doc.Accounts` setting `Tokens = accountTokenSnapshot(acc.AuthIndex)`. Bump `pluginVersion` to `0.12.0`.
- [ ] **Step 4: Run** `go test ./...` and `gofmt -l .`. Expected: all pass, `gofmt` prints nothing.
- [ ] **Step 5: Commit** `feat: report token counters per account in the usage document`.

**Running Go:** Go is not installed in the agent pod. Run tests in a one-shot container:
`tar -cz --exclude=.git --exclude=dist . | /scripts/t3-run golang:1.26 -- sh -c 'mkdir /w && cd /w && tar -xz && go test ./... && test -z "$(gofmt -l .)"'`.

---

### Task 2: `get-quota` per-account history and activity

Repo: this plugin repo, branch `t3/per-account-usage`.

**Files:**
- Modify: `get-quota` (snapshot ~lines 104-117, activity ~lines 123-150, account output ~lines 206-214)
- Create: `tests/fixtures/usage-account-tokens.json` (contract-2 shape: provider `acme`, two accounts `1111111111111111`, `2222222222222222` with `tokens`, plus `legacy` single account)
- Test: `tests/test-get-quota.sh`

**Interfaces:**
- Produces, in `get-quota` output:
  - `providers[].accounts[].authIndex` (string, copied from the payload).
  - `providers[].activity[]` entries gain optional `accounts`: object `authIndex` → `{requests, failed, tokens}`, where `tokens` is model id → day delta (only values > 0). Present only for days with at least one interval whose previous snapshot had `accounts`.
- History snapshot: `providers[].accounts`: `[{authIndex, success, failed, tokens}]` (`tokens` = payload account `tokens // {}`).

- [ ] **Step 1: Write failing tests** in `tests/test-get-quota.sh`, following the existing history tests (they seed `history-*.jsonl` and run the script):
  - `output carries authIndex per account`: `.providers[0].accounts[].authIndex` equals the fixture values.
  - `per-account day deltas`: seed one snapshot with `accounts` (a1 tokens `{m: 100}`, b2 `{m: 10}`), run with fixture a1 `{m: 160}`, b2 `{m: 40}` → today's `accounts["1111111111111111"].tokens.m == 60`, `accounts["2222222222222222"].tokens.m == 30`.
  - `account counter reset uses delta rule`: previous a1 `{m: 500}`, current a1 `{m: 20}` → day value `20`, never negative.
  - `no split when previous snapshot lacks accounts`: seed snapshot without `accounts` → today's entry has no `accounts` key, provider `tokens` unchanged.
  - `account missing from previous snapshot counts from zero`: previous snapshot has `accounts` with only a1 → b2 day value equals its current total.
- [ ] **Step 2: Run** `bash tests/test-get-quota.sh` with jq ≥ 1.7. Expected: new tests FAIL.
- [ ] **Step 3: Implement** in the snapshot and activity jq programs. Per-account day value per model: `delta(cur; prev // 0)` where `prev` is the previous snapshot's same `authIndex` value; skip an interval's account part when the previous snapshot has no `accounts`. Sum intervals per date like the provider totals.
- [ ] **Step 4: Run** all `tests/test-*.sh`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(get-quota): keep usage per account`.

---

### Task 3: Widget account view layer

**Files:**
- Modify: `CliproxyQuotaWidget.qml` (root properties near `activity`, `usageStats`, `modelFamilies`, lines ~77-200)
- Create: `tests/test-account-view.sh` (node `vm`, same extraction style as `tests/test-model-families.sh`)

**Interfaces:**
- Consumes: Task 2 output fields.
- Produces on `root`:
  - `readonly property var accountPalette` — list of colours (builder picks; must read as a 2 px outline over every `familyPalette` fill).
  - `readonly property var accountColors` — object `authIndex` → colour, by position in `pillProvider.accounts`; `{}` when fewer than 2 accounts.
  - `readonly property bool showAccountSplit` — `Object.keys(accountColors).length >= 2 && activity.some(e => !!e.accounts)`.
  - `property string selectedAccount: ""` — `""` means All. Reset to `""` when the focused provider id changes, when the popout opens, and when the selected `authIndex` is no longer in `pillProvider.accounts`.
  - `function viewEntry(entry)` → `entry` when `selectedAccount === ""`, else `{date, requests, failed, tokens}` from `entry.accounts[selectedAccount]` (zeros and `{}` when absent).
  - `readonly property var viewActivity` — `activity.map(viewEntry)`.
  - `usageStats` reads `viewActivity` instead of `activity`.
  - `function accountTokens(entry, authIndex, family)` → that account's tokens in `entry` for `family` (all families when `family` is null).
  - `function clampedBoxes(total, parts)` — `parts` is an array of `{authIndex, value}` in account order; returns the same shape, each value ≥ 0, running sum capped at `total`.
  - `modelFamilies`, `modelTotals` and the Daily Activity `maxValue` keep reading `activity` (All).

- [ ] **Step 1: Write failing tests** in `tests/test-account-view.sh`:
  - `accountColors` empty for one account; two accounts get `accountPalette[0]` and `[1]` by list order.
  - `showAccountSplit` false when no activity entry has `accounts`.
  - `viewEntry` with `selectedAccount = "2222222222222222"` returns that account's `requests` and `tokens`; with an unknown id returns zeros.
  - `usageStats` under a selected account sums only that account (today and 7 days).
  - `clampedBoxes(100, [{authIndex: "a1", value: 70}, {authIndex: "b2", value: 50}])` → values `[70, 30]`; `clampedBoxes(100, [{authIndex: "a1", value: 20}])` → `[20]` (rest stays un-outlined).
- [ ] **Step 2: Run** `bash tests/test-account-view.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the properties and functions above in `CliproxyQuotaWidget.qml`.
- [ ] **Step 4: Run** all `tests/test-*.sh`. Expected: all pass.
- [ ] **Step 5: Commit** `feat(popout): per-account view of usage data`.

---

### Task 4: Widget visuals and chips

**Files:**
- Modify: `CliproxyQuotaWidget.qml` (Token Consumption card ~908, Daily Activity bars ~1030-1100, Models bars ~1170-1185, account card border ~1281)
- Modify: `translations.js` (`"All"`, fr `"Tous"`, es `"Todos"`)
- Modify: `CONTEXT.md` (term **Account colour**), `PLAN.md` (account list + usage cards description)
- Test: `tests/test-qml-syntax.sh`, `tests/test-translations.sh` (existing)

**Interfaces:**
- Consumes: everything Task 3 produces.

- [ ] **Step 1: Chips row** above Token Consumption, visible when `root.showAccountSplit`: `All` chip, then one chip per account in list order with a colour swatch (`accountColors[authIndex]`) and `label || account`. Selected chip uses the provider-tab focused style (`Theme.primary` border at 0.45 alpha, 0.16 fill). Click sets `root.selectedAccount`.
- [ ] **Step 2: Daily Activity bars:** family fill uses `root.viewEntry(dayColumn.modelData)`; scale still `activityCard.maxValue`. When `root.showAccountSplit`, overlay a bottom-anchored Column of transparent `Rectangle`s with `border.width: 2`, `border.color` = account colour, `radius: 3`, height `max(3, 64 * value / maxValue)` from `clampedBoxes(dayTotal, parts)`; under a chip only the selected account's box. Tooltip lists per-account totals when split exists.
- [ ] **Step 3: Models bars:** bar height 10 when `root.showAccountSplit` (else 6). Fill width from the view's family total over `modelFamilies[0].total` (All). Overlay a Row of outlined segments, widths `max(3, barWidth * value / modelFamilies[0].total)` from `clampedBoxes`.
- [ ] **Step 4: Account card border:** when `accountColors[authIndex]` exists, `border.width: 2`, `border.color` = that colour, also for unhealthy accounts; otherwise current PR #32 behaviour.
- [ ] **Step 5: Translations and docs** as listed in Files.
- [ ] **Step 6: Run** all `tests/test-*.sh`. Expected: all pass, `test-translations` counts the new key.
- [ ] **Step 7: Commit** `feat(popout): account outlines in usage bars and account chips`.

---

### Task 5: Ship and verify live

- [ ] **Step 1:** Review gate on the bridge branch, PR to `SpyrosPsarras/pi-cliproxyapi-bridge`, merge after CI and owner OK.
- [ ] **Step 2:** Build `pi-bridge-v0.12.0.so` per the bridge README (`build.sh`, SDK v7.2.93) in a one-shot golang container. Ask the owner for the deploy host and confirmation, then deploy per README "Deploy without restarting CLIProxyAPI" (new versioned file, edit `store.version`).
- [ ] **Step 3:** Confirm a v2 `get-quota` run on `laptop-ts` shows `tokens` on each account.
- [ ] **Step 4:** Review gate on the plugin branch, install the 3 runtime files on `laptop-ts`, reload the plugin, capture only the popout (chips, outlines, card borders). Restore the laptop clone afterwards.
- [ ] **Step 5:** PR to `SpyrosPsarras/dms-cliproxy-quota` with the spec and plan, merge after CI and owner OK. The repo is public: PR images use synthetic data only, never the live popout with real account names.
