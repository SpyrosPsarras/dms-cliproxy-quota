# dms-cliproxy-quota

A DankMaterialShell taskbar plugin that shows provider quota and account health
from CLIProxyAPI, so quota is visible without opening pi or any other tool.

## Language

**Provider**:
A model vendor as CLIProxyAPI names it (`claude`, `codex`, `github-copilot`).
One carousel page per provider.
_Avoid_: subscription, service, vendor

**Account**:
One credential CLIProxyAPI holds for a provider. A provider may have several;
the proxy routes each request to whichever live account has headroom.
_Avoid_: auth file, subscription, user

**Live account**:
An account that is not `disabled`, not `unavailable`, is `supported`, and
reports at least one group. Only live accounts feed the aggregate.

**Group**:
One quota window an account reports (`five-hour`, `seven-day`, ...). Group ids
and labels are data from the server; the plugin never special-cases them.
_Avoid_: window, limit, bucket

**remainingFraction**:
Fraction of a group's quota still available, 0–1. It is REMAINING, never used;
inverting it is a silent error.
_Avoid_: usage, used, consumed

**Aggregate**:
A provider's headline number: the worst group within each live account, then
the best of those across the provider's live accounts.
_Avoid_: total, average

**Focused provider**:
The carousel page currently selected. It alone drives the pill's ring.
Persisted across restarts.
_Avoid_: active provider, current provider

**Pill**:
The taskbar element: a ring for the focused provider's aggregate, plus a
warning glyph for a problem on any provider.

**Contract version**:
The response shape negotiated via the `X-Pi-Contract` request header and echoed
back. The plugin pins 2.
_Avoid_: schema, API version

**Payload schema**:
The `schemaVersion` field inside the response body. Moves independently of the
contract version; contract 2 currently ships payload schema 1.
_Avoid_: contract

**Stale**:
Data the plugin cannot vouch for as current: the server marked it stale, or the
fetch failed. Stale numbers are dimmed and never presented as live.
