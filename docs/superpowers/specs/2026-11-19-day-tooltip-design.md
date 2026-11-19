# Daily Activity hover: mini bar with labels

## Intent

Hovering a Daily Activity bar shows one line of text. It is cut off after
the first model, it lists the biggest model first while the bar draws it at
the bottom, and a horizontal line gives no hint which end of a vertical bar
is which. The owner wants a hover that reads at a glance, in the same
vertical shape as the bar.

## Goals

- The hover shows a tall copy of the hovered day's bar with every slice
  labelled beside it, so up and down match the bar.
- Account parts (when the account split is shown) appear as outlined
  brackets on the other side of the mini bar, in each account's colour.
- Nothing is cut off; the text is smaller than today's tooltip.

## Non-goals

- No hover on the Models card.
- No change to the bars, chips, colours or numbers themselves.

## Approaches considered

1. T1, vertical list in bar order (rejected by owner).
2. **Chosen: T2**, mini bar with labels (mockup "T2 · Mini bar with labels").
3. T3, fixed details panel under the chart (rejected by owner).

## Design

- **Where:** the mouse-transparent overlay replaces `DankTooltipV2` for token bars
  and opens below the Daily Activity bars and day labels, centered on the hovered
  day and clamped inside the popout.
- **Header:** short weekday and date on the left, the day's total tokens
  on the right.
- **Mini bar:** fixed height (about 120 px), one slice per model family in
  the same order and colours as the day bar (biggest family at the
  bottom). Slice heights are the family's share of that day; a non-zero
  slice is at least 2 px.
- **Model labels (right of the mini bar):** one row per non-zero slice:
  name and tokens. Name as in the Models card: the version name when the
  family has one version, else the family name. Each label sits at its
  slice's vertical centre; labels that would overlap are pushed apart to a
  minimum row height, keeping their order, and kept inside the mini bar's
  height.
- **Account brackets (left of the mini bar):** only when
  `showAccountSplit` and the day has account tokens. One outlined bracket
  per coloured account, in the day bar's box order and sizes (from
  `clampedBoxes`, scaled to the mini bar), in the account colour; label
  (`label || account`, elided to about 110 px) and tokens at the bracket's
  centre, same push-apart rule. Un-attributed space stays empty.
- **Footer:** `N requests` and, when non-zero, `· M failed`.
- **Under a chip:** the mini bar, labels and header use the selected
  account's numbers (`viewEntry`), slice proportions within that day; only
  the selected account's bracket is drawn.
- **Requests-only mode** (no token data): keep the current one-line
  tooltip.
- **Text:** `Theme.fontSizeSmall - 1`, tabular numbers where available.
- **Show/hide:** as today, on entering and leaving a day column.

## Constraints

- No hardcoded provider, model or account names (`tests/test-qml-syntax.sh`).
- New strings through `root.tr()` with fr/es entries (none expected beyond
  existing "requests" and "failed").
- The overlay must stay inside the 420 px popout.

## Left to the builder

- Exact sizes and spacing, as long as the mini bar is clearly taller than
  the day bar and labels never overlap.
- How the label push-apart is implemented, as long as it is one pure
  function with a node test.

## Delivery

One PR. Live check on the owner's desktop with synthetic data; PR images
synthetic only (public repo).
