# Daily Activity hover grouped by account

Revises `2026-11-19-day-tooltip-design.md` (placement, header, footer and
requests-only mode stay as they are).

## Intent

The hover listed the day's models on the right and the accounts on the left
with no link between them, so the owner could not tell which account used
which model. On the day the per-account bridge was deployed most usage had
no account split, which squeezed the account brackets to a few pixels.

## Goals

- Each account's part of the mini bar is filled with that account's own
  models, and its models are listed next to that part (mockup "R1 · Model
  list per part").
- Account names and tokens stay on the left, each with a bracket in the
  account colour spanning its part.
- Usage the day has no account split for is its own part, labelled
  "earlier", with a dashed muted bracket, so the parts add up to the day
  total.

## Non-goals

- No change to placement, header, footer, highlight or requests-only mode.
- No change to the day bars, chips or Models card.

## Approaches considered

M1 one mini bar per account, M3 table, and right-side variants R2 colour
chips + legend, R3 share per account, R4 biggest model + rest. The owner
picked M2 (grouped by account) with brackets on the left and R1 on the
right.

## Design

- **Parts, bottom to top** (same order as the day bar's outlines): each
  coloured account with tokens that day, in account list order, then the
  "earlier" part = day total − sum of the accounts' tokens when above 0.
  Under a chip: only the selected account's part, no "earlier" part. When
  the day has no account split (or `showAccountSplit` is false): one part
  for the whole day, no bracket, no name.
- **Part heights:** each part is at least `max(2, model rows) × rowHeight`
  tall so its labels fit; the mini bar's remaining height is shared in
  proportion to tokens. If the minimums exceed the mini bar height, the
  mini bar grows. A small gap separates parts.
- **Inside a part:** one slice per model family with tokens in that part,
  in the day bar's family order (biggest family at the bottom), sized by
  share within the part, non-zero slice at least 2 px.
- **Right:** per part, one row per slice in the same top-to-bottom order:
  colour swatch, model name (the family's only version name, else the
  family name), tokens; rows centred on the part. "earlier" rows muted.
- **Left:** per part, name (`label || account`, elided at about 110 px,
  or `tr("earlier")`) and tokens, right-aligned and centred on the part,
  then a left-open bracket in the account colour (2 px), dashed and muted
  for "earlier".
- `spreadLabels` is no longer needed; remove it and its tests.

## Constraints

- No hardcoded provider, model or account names.
- New string "earlier" with fr "plus tôt", es "antes".
- Overlay still inside the popout margins.

## Delivery

One PR, live check with synthetic data, PR images synthetic only.
