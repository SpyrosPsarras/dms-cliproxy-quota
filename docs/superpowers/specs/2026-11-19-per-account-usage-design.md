# Per-account usage in the popout

## Intent

A provider can have more than one account. Token
Consumption, Daily Activity and Models add up all of them, and nothing shows
which account used how much. The owner wants to see it at a glance, in a
screenshot, without reading numbers: which part of each bar came from which
account.

## Goals

- Each account has one colour. Its account card border uses it.
- Inside every Daily Activity bar and every Models bar, an outlined box in
  each account's colour marks that account's part. The bar fill stays the
  model-family colours it has today.
- Account chips above the usage cards: `All` and one chip per account. A chip
  filters Token Consumption, Daily Activity and Models to that account.
- Totals stay as they are when `All` is selected.

## Non-goals

- No change to which account drives the quota rings and the pill (the
  headline account from PR #32).
- No per-account split for days before the change is deployed.
- No change for providers with a single account: no account colour, no
  outlines, no chips; the PR #32 accent border and the error border stay.

## Anti-goals

- A screenshot that needs a legend or numbers to tell accounts apart.
- Outlines that hide or replace the model colours in the bars.

## Approaches considered

1. Account colours as bar fill, stacked by account (rejected: loses model
   colours in the bars).
2. Model-coloured bars with a thin account strip under each bar (rejected:
   too small to read at a glance).
3. Usage charts inside each account card (rejected by owner: the totals stay
   where they are).
4. **Chosen:** model-coloured bars with outlined account boxes inside them,
   account colour shared with the card border (mockup V1), plus account
   filter chips (mockup O3).

## Data: bridge (`SpyrosPsarras/pi-cliproxyapi-bridge`)

The bridge already receives every request with `Provider`, `Model`,
`AuthIndex` and token counts (`usage.handle`, `tokenstats.go`). It sums them
by provider and model only, so the account is lost.

- Keep a second set of cumulative counters keyed by provider, model and
  `authIndex`, using the same rules as `recordTokenUsage` (cached counted
  once; total falls back to input + output).
- Attach them to each account as `tokens` (an object of model id to
  cumulative `total`) on every serve, next to `doc.Models =
  tokenModelSnapshot()` in `shapeForContract`, not in the cached document.
  That keeps per-account counters in step with the provider counters.
  Contract v2 only; v1 output stays byte-identical.
- The document-level `models` array stays unchanged, so older plugin
  versions keep working.
- Counters reset when the bridge restarts, like the existing ones.

## Data: plugin (`get-quota`)

- The history snapshot gains, per provider, `accounts`: `authIndex`,
  `success`, `failed`, `tokens` (copied from the account).
- `activity` per day gains `accounts`: `authIndex` to `{requests, tokens}`,
  computed with the same `delta()` rule as the provider totals, so a bridge
  restart or counter reset does not produce negative or huge values.
- Snapshots written before this change have no `accounts`. Days built only
  from them have no account split.
- If the bridge sends no `tokens` per account (old bridge), the plugin shows
  no outlines and no chips, and behaves as today.

## UI (`CliproxyQuotaWidget.qml`)

- **Account colour:** by the account's position in the provider's account
  list, from a palette of its own. Account card border uses it, 2 px, for
  every account of a provider with 2+ accounts. This replaces the accent
  border from PR #32; the `shown` tag stays.
- **Unhealthy accounts:** the account colour wins over the red error border
  (owner may correct). The red status dot, red tags and error text still
  mark the problem.
- **Daily Activity bars:** fill unchanged. On top, one outlined box per
  account with usage that day, stacked bottom-up in account order, each box's
  height = that account's share of the day's tokens. No fill inside the
  boxes. Days with no account split draw no boxes.
- **Models bars:** same idea, horizontal: one outlined segment per account,
  left to right in account order, widths by that account's share of that
  family's 7-day tokens.
- **Chips:** a row above Token Consumption, only for providers with 2+
  accounts that have account-split data. `All` first, then one chip per
  account with its colour swatch and masked label. Selected chip uses the
  accent outline, like the provider tabs.
- **Chip filter:** an account chip makes Token Consumption (tokens and
  requests), Daily Activity and Models use only that account's numbers. The
  bars then draw only that account's box. Quota rings, pill and Accounts
  list do not change.
- **Chip state:** not saved. Resets to `All` when the provider tab changes or
  the popout reopens.
- New UI strings go through `root.tr()` with fr/es entries.

### Calls made after the builder check

- **Fixed colours and scale under a chip:** model-family colours and the
  Daily Activity bar scale come from the `All` data and do not change when a
  chip is selected. A filtered bar is shorter than its `All` bar, so the
  screenshot shows the account's real size. This needs a filtered view layer
  over the `All` data, not a filtered `activity` passed through the existing
  properties.
- **Partial split:** each account box is sized against the bar's full
  total. Tokens with no account (snapshots from before the change, or an
  `authIndex` no longer listed) are left as un-outlined space at the top of
  the bar or the right of the Models bar. Under a chip, a day with no data
  for that account draws no bar.
- **Accounts that left the list:** their history still counts in `All`. They
  get no chip and no colour; their part of each bar is the un-outlined
  space above. Colours follow the current list order, so removing an account
  can shift the colours of the ones after it.
- **Single-account providers:** unchanged, see non-goals.

## Constraints

- Masked account names can repeat; key everything by `authIndex`.
  CLIProxyAPI derives it from the auth file name or credential identity
  (`sdk/cliproxy/auth/types.go`, `EnsureIndex` / `stableAuthIndex`, a
  SHA-256 prefix), so it survives proxy and bridge restarts. Re-adding an
  account under a new auth file gives it a new `authIndex`; it then counts
  as a new account.
- `tests/test-qml-syntax.sh` bans hardcoded provider, model and group names;
  account handling must stay data-driven.
- The popout is ~420 px wide; boxes for a small share (for example 13% of a
  short bar) must still be visible: give every non-zero box a minimum height
  or width of about 3 px.
- The bridge is a fork of `abix5/pi-cliproxyapi-bridge`; keep the change
  small enough to offer upstream.
- Deploying the bridge changes a running service: confirm with the owner
  first and follow its README "Deploy without restarting CLIProxyAPI".

## Left to the builder

- The account palette values, as long as each colour stays readable as a
  2 px outline over every model-family fill (an inner 1 px gap in the card
  colour is one way).
- Exact field names inside `activity` and the snapshot, as long as tests
  cover restart and missing-data cases.
- How chips scroll if a provider has many accounts.

## Delivery

Two PRs: bridge first (with Go tests), then plugin (with `get-quota` tests
and QML syntax tests). Live check on the owner's desktop as for PR #32.
