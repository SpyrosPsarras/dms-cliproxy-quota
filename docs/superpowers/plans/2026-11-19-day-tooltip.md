# Daily Activity hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one-line Daily Activity tooltip with a vertical mini bar whose slices and account brackets are labelled beside it.

**Architecture:** Pure layout functions on `root` (testable with node `vm`) compute the day detail: slices, account brackets and label positions. A custom overlay Item inside the popout draws them next to the hovered bar.

**Tech Stack:** QML/Quickshell (DankMaterialShell widget), node `vm` tests.

**Spec:** `docs/superpowers/specs/2026-11-19-day-tooltip-design.md`

## Global Constraints

- No hardcoded provider, model or account names (`tests/test-qml-syntax.sh`).
- Strings through `root.tr()`; reuse existing keys "requests" and "failed".
- The overlay stays inside the 420 px popout and never takes mouse input.
- Slice order and colours match the day bar: `root.modelFamilies` reversed top to bottom, biggest family at the bottom.
- Under a chip, numbers come from `root.viewEntry(entry)`; brackets only for `root.selectedAccount`.
- Requests-only mode (`activityCard.hasTokens` false) keeps the current one-line `dayTip`.
- No code comments beyond a one-line why.

## Review Focus

1. Many tiny slices on one day (labels crowd): push-apart keeps order and stays inside the bar height; when they cannot fit, rows may extend evenly beyond but never overlap. Test in Task 1.
2. A day with zero tokens under a chip: no overlay content beyond header/footer, no division by zero. Test in Task 1.
3. Hover on the rightmost bar: overlay opens to the left and stays inside the popout. Checked live in Task 2.
4. Account sums above the day total: brackets clamped (`clampedBoxes`) so they never exceed the mini bar. Test in Task 1.
5. Long masked account names: elided, overlay width unchanged. Checked live in Task 2.

---

### Task 1: Day detail layout functions

**Files:**
- Modify: `CliproxyQuotaWidget.qml` (root functions near `accountBoxes` / `clampedBoxes`)
- Test: `tests/test-account-view.sh` (extend) or new `tests/test-day-detail.sh` in the same node `vm` style

**Interfaces:**
- Produces on `root`:
  - `function spreadLabels(centres, rowHeight, height)` → array of y positions (top of each row), same order as `centres` (ascending), each `y[i+1] >= y[i] + rowHeight`, first `>= 0`; when the rows fit, last `<= height - rowHeight`; each row as close to `centre - rowHeight / 2` as these rules allow.
  - `function dayDetail(allEntry, barHeight)` → `{ date, total, requests, failed, slices: [{name, color, tokens, y, h}], brackets: [{authIndex, name, color, tokens, y, h}] }`. `total`, `requests`, `failed` and slice tokens from `root.viewEntry(allEntry)`; slices one per non-zero family in bar order (top to bottom), heights proportional to the view total within `barHeight`, non-zero slice at least 2 px, y measured from the top; name = the family's only version name, else the family name. Brackets only when `root.showAccountSplit && root.hasAccountTokens(allEntry)`: from `root.accountBoxes(root.dayTokens(allEntry), [allEntry], null)` (already filtered to the selected account under a chip), stacked bottom-up in the same order as the day bar boxes, scaled against the All day total when no chip is selected and against the view total under a chip, clamped to `barHeight`; `name` = `label || account`.

- [ ] **Step 1: Write failing tests:**
  - `spreadLabels([10, 12, 14], 12, 120)` → strictly increasing, gaps ≥ 12, first ≥ 0.
  - `spreadLabels([60], 12, 120)` → `[54]`.
  - `spreadLabels([2, 118], 12, 120)` → `[0, 108]`.
  - `dayDetail` on a two-account synthetic day (All): slices in reversed family order, heights sum to `barHeight` within 1 px per slice, brackets two entries with heights proportional to account tokens.
  - `dayDetail` under `selectedAccount` = second account: total equals that account's tokens, one bracket.
  - `dayDetail` with account sums above the day total: bracket heights sum ≤ `barHeight`.
  - `dayDetail` for a day with zero tokens under a chip: `slices` and `brackets` empty, no NaN.
- [ ] **Step 2: Run the test file.** Expected: FAIL.
- [ ] **Step 3: Implement** the two functions.
- [ ] **Step 4: Run all `tests/test-*.sh`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(popout): layout for the Daily Activity hover`.

### Task 2: Hover overlay

**Files:**
- Modify: `CliproxyQuotaWidget.qml` (Daily Activity card: replace `dayTip.show(...)` for the token case; add the overlay Item inside `popoutRoot`)

**Interfaces:**
- Consumes: `root.dayDetail`, `root.spreadLabels`.

- [ ] **Step 1: Overlay Item** inside the popout content (a child of `popoutRoot` with high `z`), `visible` while a day is hovered and `activityCard.hasTokens`, holding the hovered entry and anchor item. Background and radius like other cards (`Theme.surfaceContainerHigh`, `Theme.cornerRadius`), border `Theme.outlineLight`. Position: map the hovered day column to `popoutRoot`; place right of it with `Theme.spacingS` gap if it fits, else left; `y` = Daily Activity card top; clamp to `popoutRoot` bounds.
- [ ] **Step 2: Content:** header (weekday + `d MMM` via `toLocaleDateString`, total via `formatTokens`), body Row of [brackets column | mini bar 18 px wide, height 120 | model labels column], footer (`requests`, optional `failed`). Labels use `spreadLabels` with row height = text height; brackets are left-open outlined rectangles (`border.width: 2`, account colour) with label + tokens; labels `Theme.fontSizeSmall - 1`; account names elide at 110 px.
- [ ] **Step 3: Wire hover:** day column `onEntered` sets the hovered entry/item when `hasTokens`, else keeps `dayTip.show` with the old one-line text; `onExited` clears. The old `dayTooltip` keeps only what the requests-only case needs.
- [ ] **Step 4: Run all `tests/test-*.sh`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(popout): vertical hover for Daily Activity bars`.
