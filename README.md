# CLIProxyAPI Quota

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) taskbar
plugin that shows how much provider quota remains behind your
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) server — every
provider, every quota group, without opening another tool.

![Screenshot](<img width="390" height="931" alt="image" src="https://github.com/user-attachments/assets/dcfd9540-36db-4300-adf6-81f7c81809de" />
)

## Requirements

**Your CLIProxyAPI server must run the
[pi-bridge](https://github.com/abix5/pi-cliproxyapi-bridge) plugin.** This is
not optional: stock CLIProxyAPI has no endpoint that reports remaining quota
or reset times, and everything its management API does offer requires the
full-admin management key. The bridge turns provider quota into a resource
route readable with an ordinary API key, cached server-side for 120 s so the
widget can never contribute to a provider rate limit. Without the bridge the
widget says "server has no quota plugin (pi-bridge)" and stops there.

On the desktop: DankMaterialShell, `curl`, `jq`. Optional: `secret-tool`
(libsecret) for reading the API key from KeePassXC or any other
freedesktop Secret Service vault.

## What you get

- **Taskbar pill** — a ring filled with what *remains* of the focused
  provider's quota: the worst group within each live account, then the best
  across the provider's live accounts — the account your proxy would route to
  next. A warning glyph when any provider has an account that is not serving
  — disabled, unavailable, or (when supported) in a non-active state — on any
  page. An error
  string on an account that is otherwise serving traffic (an unreadable quota
  meter upstream, say) is degraded telemetry: shown in the account detail,
  never a warning. Dimmed with `?` the
  moment the data stops being live: old numbers are never dressed up as
  current.
- **Popout carousel** — one page per provider, arrows or ←/→ to navigate.
  Each page: the aggregate's quota bars with reset countdowns, then every
  account behind it — health, last request, success/failed counters,
  per-group bars. Disabled accounts are listed and labelled, never silently
  dropped; an account whose provider reports no quota says "no quota
  reported" instead of pretending 0%. Header shows the server cache's age and
  a refresh button.
- **Daily activity and tokens by model.** Each provider page charts requests
  per day for the last week, and — when the bridge reports per-model token
  counters (pi-bridge 0.10.0 or newer, contract v2 `models` field) — a
  stacked tokens-per-model chart with a dynamic legend. Counters are
  cumulative on the server and vanish when it restarts; the plugin snapshots
  them on every poll, diffs successive snapshots, and sums the deltas per
  local day. When a counter drops between two polls the plugin reads it as a
  restart and counts the new value as traffic since the restart, so a restart
  costs at most one poll interval of history instead of the whole day. Models are
  data: whatever the bridge reports renders, nothing is named in code.
- **Providers are data, not code.** Group ids, labels, and providers come
  from the bridge and are never used in rendering or aggregation decisions;
  the one exception is picking an icon, and an unknown provider gets a
  generic one. A provider that ships a new quota group tomorrow renders
  today, and a static test bans provider, group, and model names from the
  source outside that icon map.

## Installation

```sh
git clone https://github.com/SpyrosPsarras/dms-cliproxy-quota \
  ~/.config/DankMaterialShell/plugins/cliproxyQuota
```

Then enable **CLIProxyAPI Quota** in DMS Settings → Plugins.

## Configuration

Out of the box the widget needs nothing on a machine that already runs
[pi](https://github.com/badlogic/pi-mono) with the `pi-cliproxyapi` extension:
endpoint and API key are read from pi's config on every fetch.

The API key is resolved through a three-source chain, first hit wins. Keys
from the first two sources live only in the process's memory — the widget
never writes a resolved key anywhere:

1. **Secret Service vault** — a lookup command, default
   `secret-tool lookup Title "cliproxyapi api key"`. Create a KeePassXC entry
   with that title and you are done; any `secret-tool` invocation works if
   you name things differently.
2. **pi's config** — `proxy.apiKey` from
   `~/.pi/agent/pi-cliproxyapi/config.json`, understanding pi's `!command`
   and `$ENV` forms.
3. **A literal key in the widget settings** — the last resort, and the one
   source that does sit on disk: DMS stores plugin settings as plaintext
   JSON, readable by anything that can read that file, and this key spends
   real quota. Prefer the vault.

Settings: vault lookup command, endpoint override (any form works — a pasted
`/v1` base is stripped to its origin), literal key, refresh interval. The
endpoint override matters when the widget should watch a different proxy than
pi uses, or when pi is not installed at all.

## How it works

One shell script, `get-quota`, owns everything that can fail: the key chain,
endpoint normalization, HTTP against the bridge's usage route (contract
version 2 pinned via `X-Pi-Contract`), staleness, and aggregation. It prints
one flat JSON document; the QML renders it without branching. Results are
cached locally for 60 s per endpoint — behind the key chain, so a lost key or
a switched endpoint is reflected immediately, never papered over by cache.
The refresh button runs `get-quota --force`, which skips the local cache and
asks the server to refresh its own with `?refresh=1`; the server rate-limits
that to its cache TTL, so a mashed button degrades to a normal read.

All network traffic is between the widget and your CLIProxyAPI server, using
an ordinary API key on a resource route: the widget cannot administer the
proxy even if its configuration leaks.

## Tests

```sh
for t in tests/test-*.sh; do bash "$t"; done
```

Everything runs offline against fixtures through a curl shim — including the
guard for the one silent bug this design fears most: `remainingFraction` is
*remaining*, and a full group must render as a full, healthy ring.

## License

MIT — see [LICENSE](LICENSE). Test harness layout descends from
[titeya/dms-claudecode](https://github.com/titeya/dms-claudecode). Provider
logo assets carry their own notices — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
