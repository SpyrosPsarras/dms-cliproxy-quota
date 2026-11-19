# Hover grouped by account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the Daily Activity hover, group the mini bar and the model labels by account, with account brackets on the left and an "earlier" part for unsplit usage.

**Architecture:** Replace `dayDetail`'s flat slices and brackets with a list of parts, each holding its own slices and size. The overlay draws one row group per part: left label + bracket, mini bar part, right model rows.

**Tech Stack:** QML/Quickshell (DankMaterialShell widget), node `vm` tests.

**Spec:** `docs/superpowers/specs/2026-11-19-hover-by-account-design.md`

## Global Constraints

- No hardcoded provider, model or account names (`tests/test-qml-syntax.sh`).
- New string "earlier": fr "plus tôt", es "antes"; other strings reuse existing keys.
- Part order bottom to top: coloured accounts in account list order, then "earlier".
- Slice order inside a part: day bar family order, biggest family at the bottom.
- Placement, header, footer, hovered-bar highlight and requests-only `dayTip` unchanged.
- No code comments beyond a one-line why.

## Review Focus

1. Deploy-day shape: one huge "earlier" part and two tiny accounts: every part keeps its minimum height and labels never overlap. Test in Task 1.
2. Under a chip: one part, no "earlier", numbers from `viewEntry`. Test in Task 1.
3. Account sums above the day total: no negative "earlier", parts never exceed the bar. Test in Task 1.
4. Day with no account split: one part, no bracket, rows for all families. Test in Task 1.
5. Account with tokens in a family the day total lacks (data mismatch): its slice still shows; nothing NaN. Test in Task 1.

---

### Task 1: Grouped day detail and overlay

**Files:**
- Modify: `CliproxyQuotaWidget.qml` (`dayDetail`, remove `spreadLabels`; overlay content inside `dayOverlay`)
- Modify: `translations.js` (`"earlier"`)
- Test: `tests/test-account-view.sh` (replace the `spreadLabels` and old `dayDetail` tests)

**Interfaces:**
- Produces: `function dayDetail(allEntry, rowHeight, minBarHeight)` → `{ date, total, requests, failed, height, parts: [{ key, name, color, dashed, tokens, y, h, slices: [{ name, color, tokens, y, h }] }] }`. `parts` top to bottom (index 0 is the top part); `key` is the `authIndex`, `"earlier"`, or `"day"` for an unsplit day; `name` is `""` for `"day"`; `color` is the account colour, `Theme.surfaceVariantText`-like muted colour for `"earlier"` (pass it in via an existing Theme property), `""` for `"day"`; `dashed` true only for `"earlier"`; `y`/`h` within the mini bar; slice `y` relative to its part; `height` = mini bar height actually used (≥ `minBarHeight`).

- [ ] **Step 1: Write failing tests** (synthetic ids and names):
  - Deploy-day: total 578, accounts A 37 (families X 31, Y 6), B 6 (X 5, Z 1), rowHeight 14, minBarHeight 120 → parts keys top to bottom `["earlier", B, A]`; earlier tokens 535; each part `h >= max(2, slices) * 14`; parts do not overlap and stay within `height`; slices inside each part ordered with the biggest family last.
  - Chip on B: one part B, no `"earlier"`, total 6.
  - Account sums 700 over a day total 578: no `"earlier"` part, all `h > 0`, last part ends at `height`.
  - Unsplit day: one part `"day"`, `name === ""`, slices for every family with tokens.
  - Mismatch: account has tokens in a family missing from the day totals → that slice present, no NaN anywhere.
- [ ] **Step 2: Run** `bash ./tests/test-account-view.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `dayDetail` as specified; delete `spreadLabels`.
- [ ] **Step 4: Overlay:** replace the brackets column, mini bar and model labels with a Column of parts (top to bottom); each part is a Row of [left label block right-aligned, 110 px name limit | bracket 2 px, dashed for earlier (a dashed look may be drawn with short segments or `Theme`-muted solid line if QML has no dashed border) | part bar 18 px with slices | model rows with 9 px swatch, name, tokens], all of height `part.h`, separated by the part gap. Keep header, footer, placement and highlight.
- [ ] **Step 5: Add** `"earlier": { fr: "plus tôt", es: "antes" }` to `translations.js`.
- [ ] **Step 6: Run all `tests/test-*.sh`.** Expected: PASS.
- [ ] **Step 7: Commit** `feat(popout): group the Daily Activity hover by account`.
