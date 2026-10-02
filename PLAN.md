# dms-cliproxy-quota — plan

A DankMaterialShell taskbar plugin that renders provider quota and account health
straight from CLIProxyAPI, with no knowledge of which subscription or API sits behind
any provider. The goal: see quota at a glance without opening pi or any other tool.

Vocabulary is pinned in `CONTEXT.md`; this plan uses those terms.

## Source of truth

One endpoint, one ordinary API key, no fallback routes:

```
GET  {origin}/v0/resource/plugins/pi-bridge/usage
GET  {origin}/v0/resource/plugins/pi-bridge/usage?refresh=1
Authorization: Bearer <ordinary CLIProxyAPI api key>
X-Pi-Contract: 2
```

**Hard requirement: CLIProxyAPI with the
[`pi-bridge`](https://github.com/abix5/pi-cliproxyapi-bridge) plugin installed.**
Stock CLIProxyAPI cannot serve this widget: no management endpoint returns remaining
quota or reset times, and every management endpoint demands the full-admin management
key (verified against the official management API docs, 2026-08-28). The bridge is
what turns provider quota into a **resource** route readable with an ordinary API
key — the widget cannot administer the proxy even if its config leaks. This
requirement goes in the README's first section, and the widget enforces it at
runtime: a 404 on the route renders as "server has no quota plugin (pi-bridge)",
not a generic error. Anything else not-200 is shown as an error — no retry against
legacy paths, no sidecar.

`pi-bridge` is the only component that calls provider quota endpoints, and it caches
for 120 s precisely so clients poll it freely. The widget can never contribute to a
provider rate limit. A live capture is in `tests/fixtures/usage-contract2-live.json`.

### Why this and not the management API

| Candidate | Verdict |
| --- | --- |
| `GET /v0/management/usage` | Removed in current CLIProxyAPI; was in-memory only and wiped on restart |
| `GET /v0/management/usage-queue` | A destructive pop. Reading it steals records from any other consumer |
| `GET /v0/management/api-key-usage` | Non-destructive but request counts only, no quota |
| `GET /v0/management/auth-files` | Needs the management key — full admin handed to a taskbar widget |
| `pi-bridge/usage` | Health **and** normalized quota, ordinary key, cached 120 s server-side |

## The contract the widget renders

Contract version 2 (header), payload schema 1 (body):

```jsonc
{
  "schemaVersion": 1,
  "generatedAt": "…",
  "client": { "keyHint": "key-3fa…9c41" },
  "cache":  { "updatedAt": "…", "stale": false, "ttlMs": 120000 },
  "accounts": [{
    "provider": "claude", "account": "s***@example.com", "authIndex": "43b5…",
    "label": "…", "status": "active", "disabled": false, "unavailable": false,
    "success": 1163, "failed": 6, "lastRequestAt": "…",
    "supported": true, "error": "…",           // error optional
    "groups": [{
      "id": "five-hour", "label": "5h Session",
      "remainingFraction": 1, "resetTime": "…",  // resetTime optional
      "models": [{ "id": "…", "displayName": "…", "remainingFraction": 1, "resetTime": "…" }]
    }]
  }],
  "unsupportedProviders": []
}
```

**Agnosticism rules, non-negotiable** (enforced by `tests/test-qml-syntax.sh`):

1. No group id is ever special-cased. `five-hour`, `seven-day-fable`, `primary-window`
   are data. A provider that ships a new window tomorrow renders without a code change.
2. No provider name is ever special-cased beyond picking an icon, and an unknown
   provider gets a generic icon rather than being dropped.
3. `remainingFraction` is **remaining**, not used. Inverting it is a silent 100% error
   with no visible symptom.
4. An account with `groups: []` shows "no quota reported" — never 0%. Today
   `github-copilot` is exactly this case, with `error: upstream returned status 400`.
5. `supported: false` and `unsupportedProviders` are surfaced as informational, not as
   failures.

Pi's own footer (`status-quota.ts`) breaks rules 1–2 on purpose — it answers "how is
the model I'm typing at doing". This widget answers "how are all my providers doing"
and must not copy that mapping.

## Shape

**Popout — a carousel, one page per provider.** Arrows at the top navigate; the page
order is the server's order. Each page:

- Headline: the provider's aggregate (worst group of the live account that took
  the newest request, or the worst live account when none reports a request
  time) with one bar per group of the aggregate's account view,
  reset countdowns from `resetTime`.
- Expandable account list: every account, including disabled ones labelled as
  disabled. Per account: masked label, health line (`status`, `error`,
  `lastRequestAt`), per-group bars, `success`/`failed` counters. Disabled and
  unavailable accounts render but never feed the aggregate.
- Header: `cache.updatedAt` age and a refresh button hitting `?refresh=1` (server
  rate-limits that to its cache TTL, so a mashed button degrades to a normal read).

**Taskbar pill.** Ring = the focused provider's aggregate. If the focused provider has
no groups, a glyph instead of a ring. Warning glyph when **any** provider (not just
the focused one) has a troubled account — `disabled`, `unavailable`, or (when
supported) in a non-active status. An error string on an account that is otherwise
serving is degraded telemetry, shown in the detail, never a warning. Dimmed with `?`
when data is stale or the fetch failed — cached numbers are never presented as live.

**Focus persistence.** The focused provider is stored in plugin settings; if it
disappears from the payload, fall back to the first page.

**Per-provider opt-out.** A provider can be **untracked**: its problems stay off
the taskbar triangle and tab dot — the bell button on its page, mirrored by an
editable settings field. Its page always stays in the carousel; the widget
silences alarms, never hides data. Persisted as a comma-separated list in plugin
settings; the fetch script knows nothing about it.

**Settings.** Source (pi's config, the default, or manual endpoint + key), refresh
interval.

## Configuration sources

**Endpoint.** Default: `proxy.endpoint` from `~/.pi/agent/pi-cliproxyapi/config.json`
when that file exists, stripped to URL origin (pi stores the `/v1` OpenAI base; the
widget needs the root). Settings can override with a manual URL, also stripped to
origin. Users without pi enter the URL directly — pi is an optional convenience,
never a requirement.

**API key — a three-source chain, first hit wins, resolved in memory at every fetch,
never cached to disk, never hashed:**

1. Secret Service vault (KeePassXC, GNOME Keyring, or any freedesktop
   implementation), via a lookup command stored in settings. Documented default:
   `secret-tool lookup Title "cliproxyapi api key"` — any `secret-tool` invocation
   works, including lookup by `Uuid` for rename-proofing.
2. `proxy.apiKey` from pi's config when that file exists, resolving `!command` and
   `$ENV` forms the way pi's `resolveConfigValue` does.
3. A literal key typed into widget settings.

When every source fails (vault locked, no pi config, no literal), the widget says
"key unavailable" and dims — never a stale number shown as live. The README
recommends pointing pi's own config at the same vault lookup so the plaintext key
never sits on disk.

## Components

```
plugin.json              id cliproxyQuota, requires: [curl, jq]
get-quota                bash: key chain, fetch, contract pin, normalize, cache; flat JSON out
CliproxyQuotaWidget.qml  pill + carousel popout
CliproxyQuotaSettings.qml
translations.js
tests/                   fixtures + shell tests, harness from titeya/dms-claudecode
README.md
```

`get-quota` owns every decision that can fail: key chain, endpoint normalization,
HTTP, contract negotiation, staleness, aggregation, and flattening. The QML receives a
flat structure it renders without branching. Local cache TTL 60 s against the server's
120 s; `--force` skips it for the refresh button.

## Milestones

- **M1 — `get-quota` against the fixture.** Key chain, endpoint from pi config,
  fetch, contract version 2 pinned, normalize, aggregate, cache, `--force`. Tested
  offline against `tests/fixtures/`. Retarget CI to `main`; QML/translation tests
  skip (not fail) while no `.qml` exists.
- **M2 — pill.** Focused-provider ring, any-provider warning glyph, stale dimming.
  First installable build.
- **M3 — carousel popout.** Provider pages, arrows, aggregate headline, expandable
  account list, reset countdowns, refresh button.
- **M4 — settings.** Source selection, manual endpoint + key, interval, focus
  persistence.
- **M5 — packaging.** README with the pi-bridge requirement stated in its first
  section, screenshot, CI green on shell tests and QML syntax check.

## Risks

- **R1 — literal key in the DMS config.** Only the chain's last resort; the vault and
  pi's config come first, and the README says plainly what the literal form costs.
- **R2 — drift.** Two independent version numbers: pin **contract version** 2 via the
  header and compare the echoed `X-Pi-Contract-Latest`; check **payload schema** 1 in
  the body. Surface a one-line notice when either moves rather than silently parsing
  an old shape.
- **R3 — endpoint may be internal-only.** A CLIProxyAPI reachable only on LAN or
  VPN is the common deployment. Off-network the widget says "unreachable" and dims,
  never presents the last good numbers as current.
- **R4 — provider shape changes upstream.** Absorbed by `pi-bridge`, which describes
  provider layouts in config rather than code. The widget inherits that immunity only
  as long as it keeps agnosticism rule 1.
- **R5 — remaining vs used inversion.** Guarded by a fixture test asserting that a
  group at `remainingFraction: 1` renders full and healthy.
- **R6 — locked vault.** Sources 1 and 2 of the key chain both go through the vault
  now. Locked vault ⇒ dimmed widget until unlock (and `/cliproxyapi` reload for pi if
  it started locked). Accepted; the alternative is a plaintext key on disk.
