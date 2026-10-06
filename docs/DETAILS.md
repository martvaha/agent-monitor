# Agent Monitor

A small macOS menu-bar app for Claude subscription usage. It shows the rolling
5-hour limit, weekly limit, and live reset countdowns.

## Data-source policy

Usage must come from the cheapest source that already exists, in this order:

1. **Files the agent already writes** (Claude's status-line cache, Codex rollout
   logs), watched with FSEvents rather than polled.
2. **A direct HTTP request** to the provider's usage endpoint, using the agent's
   existing sign-in read-only (see the Claude OAuth request below).

Never launch an agent CLI (`claude`, `codex`) or scrape its TUI through a PTY to
read usage: each launch boots a full Node/Rust runtime, loads config and plugins,
and can start a session, which is far heavier than one HTTPS request. When a new
provider or window needs live data, find the HTTP endpoint the CLI itself calls
and use that. Like the Claude path, such requests must not refresh or rewrite the
agent's credentials; the agent owns its session.

## How it works

The app reads `claudeAiOauth.accessToken` (and its optional millisecond expiry)
from the existing `Claude Code-credentials` Keychain item. It makes a read-only
`GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer …`
and `anthropic-beta: oauth-2025-04-20`. Both `five_hour` and `seven_day` are
decoded from the same response, including fractional utilization and ISO 8601
reset timestamps. Additional response fields are ignored. This works with a
Claude Code session used by Zed without requiring the CLI’s status line.

Credentials are reread on each attempt, so a renewed session is picked up without
restarting the monitor. The app does not call the token-refresh endpoint or modify
Claude’s credentials: Claude Code owns session renewal. Expired or rejected tokens
cause a cooldown and an actionable message. Keychain interaction is allowed only
after clicking **Allow Keychain access**, never at startup, when opening the menu,
or during an ordinary retry. The explicit action reads the credential immediately;
the subsequent usage request still honors the endpoint cooldown. Network and
Keychain work runs off the UI thread.

Claude Code writes the item with `/usr/bin/security`, and each token renewal
resets the item's partition list to Apple tools (`apple-tool:`). That silently
revokes an **Always Allow** granted to this app every few hours. The app
therefore reads the item through `/usr/bin/security find-generic-password -w`,
the same Apple tool Claude Code uses and that the item's access list already
trusts, so no prompt appears. This is a tiny system binary rather than the agent
CLI, and it only reads. The secret passes through a private pipe and is never
logged. Background reads skip the tool while the login Keychain is locked,
because the tool would then ask for a password. If the tool fails, the app falls
back to the direct Keychain read below.

The existing credential is in the legacy login Keychain. `LAContext` alone does
not suppress that Keychain's permission UI, so reads also set
`SecKeychainSetUserInteractionAllowed`, restore its prior value afterward, and
serialize access because this switch is process-wide. This legacy item uses app
access-control lists, not biometric access control; adding a Touch ID check would
not replace the login Keychain password or authorize the app. Choose **Always
Allow** in the system prompt to authorize future reads.

Requests use an ephemeral URLSession, no cookies or response cache, a 20-second
request timeout and a 30-second resource timeout. Redirects are rejected so the
access token cannot be forwarded to another endpoint. Credentials, HTTP response
bodies, and transport error details are never logged or persisted by the app.

### Adaptive polling

| Power state | Active interval | Unchanged-usage intervals |
| --- | --- | --- |
| AC power | 2 min | 4 → 8 → 15 min |
| Battery | 5 min | 10 → 20 → 30 min |
| Low Power Mode | 10 min | 20 → 40 → 60 min |

The first successful request schedules a short follow-up. Increases in either
window, including fractional changes below the rounded UI percentage, restore
the active interval. Resetting an otherwise empty window does not count as
activity. A native recursive FSEvents stream watches `~/.claude/projects` (or
`$CLAUDE_CONFIG_DIR/projects`) for session writes. Events are batched over one
minute; no transcript contents are read and no session directories are scanned.
These local activity hints shorten idle polling and keep it active when rounded
server percentages have not yet increased. They obey the same minimum intervals
and cooldowns. Without those files, or for usage from another device, idle
intervals bound how long discovering new usage can take.
Opening the menu requests an earlier check, but cannot bypass minimum spacing
or an error cooldown. The monitor uses a single one-shot timer with scheduling
tolerance for wake-up coalescing. Power changes reschedule it through native
notifications. Sleep cancels the timer and any request; wake resumes the schedule
without trying to catch up missed requests.

Rate limits start with a five-minute cooldown; network/server failures start
with the active interval, and authentication failures start with 15 minutes.
Repeated failures double the delay up to one hour. `Retry-After` seconds or HTTP
dates take precedence when longer, with no local cap on server-requested waits.
Even `Retry-After: 0` gets a cooldown. Polling timestamps and fractional snapshots
are stored in `polling.json` beside the usage cache so relaunching preserves the
cooldown. Failures preserve the last usage reading and show it as last-known.

### Status-line integration

Claude Code 2.1.80 and newer also includes subscription rate limits in the JSON sent
to status-line commands after a normal Claude response:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
```

Agent Monitor installs a lightweight status-line bridge that writes those
fields to `~/Library/Application Support/ClaudeMonitor/usage.json`. The menu-bar
app watches that directory and updates as soon as the cache changes.

The app watches this cache for immediate local updates. Fresh status-line events
postpone the next network request, without overriding server cooldowns. Older
snapshots cannot replace newer readings, including when a bridge update arrives
during an HTTP request. The reset countdown advances locally while the popover is
visible. The bridge is optional for Zed; network polling supplies its usage.

If a status-line command already exists, the installer saves it and the bridge
forwards the original JSON to it after updating the cache. Run the bridge with
`--uninstall` to restore the previous status-line configuration.

## Codex usage

The popover also shows OpenAI Codex CLI usage beneath Claude, when Codex
data is available. Codex writes a `token_count` event with a `rate_limits` object
into `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` after each response, so no CLI
launch or PTY scraping is needed. The app checks those logs at launch, when an
FSEvents stream on the sessions tree reports writes, on a two-minute fallback
timer, and when the popover opens. Unchanged files are skipped, and changed files
are searched backward from their tails instead of being reread in full.

Codex only logs usage after a response, so an idle snapshot outlives its windows.
A window whose reset time has passed is shown as empty with no countdown until
Codex reports again; the same applies to a cached Claude reading. The menu-bar
icon redraws at the next reset and on wake.

The reader is generic over Codex's `primary`/`secondary` windows and labels each by
its `window_minutes` (5-hour ≈ 300, weekly ≈ 10080, monthly ≈ 43800), so if OpenAI
adds a 5-hour or weekly window it renders without code changes. Both absolute
(`resets_at`) and relative (`resets_in_seconds`) reset forms are supported. If a
Codex build logs `rate_limits: null`, the section stays hidden. Set `CODEX_HOME` to
point at a non-default config directory.

## Requirements

- macOS 27 (Golden Gate)
- Claude Code 2.1.80+ signed into a Claude.ai Pro or Max subscription
- Xcode 27 or Command Line Tools with the macOS 27 SDK when building from source

The `rate_limits` field appears after the first API response in a Claude Code
session.

## Build and install

```sh
./scripts/make-app.sh --install
```

This builds the app, installs it to `~/Applications`, configures the status-line
bridge in `~/.claude/settings.json`, and launches the menu-bar app. Claude Code
responses then publish usage updates to the app. Zed sessions use the same saved
sign-in and the usage polling path automatically.

The build signs the helper and app with a persistent local certificate in
`.local-signing/` (git-ignored, accessible only to the current user). Its private
key lives in a separate, password-protected Keychain that is locked after signing.
Temporary exported keys are deleted, the user's Keychain search list is restored,
and no global certificate trust settings or Claude credential permissions are
changed. A certificate-based designated requirement keeps the app recognizable
across rebuilds, unlike Swift's default ad-hoc signature tied to a specific binary.
The first signed build requires a new **Always Allow** approval. Keep
`.local-signing/` to retain that identity; deleting it or changing signing identity
requires reapproval. This local certificate is for local builds, not notarized
distribution. To use an existing signing identity instead:

```sh
CLAUDE_MONITOR_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" \
  ./scripts/make-app.sh --install
```

To build without installing:

```sh
./scripts/make-app.sh
AgentMonitor.app/Contents/Helpers/AgentMonitorBridge --install
open AgentMonitor.app
```

To remove the bridge and restore the previous status-line setting:

```sh
~/Applications/AgentMonitor.app/Contents/Helpers/AgentMonitorBridge --uninstall
```

## Verify

```sh
swift run MonitorCheck
swift build
```

The bridge can be tested without changing Claude settings or making a model
request by passing representative status-line JSON and overriding the cache path:

```sh
CLAUDE_MONITOR_CACHE_PATH=/tmp/agent-monitor-usage.json \
  swift run AgentMonitorBridge <<'JSON'
{"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":1789038000},"seven_day":{"used_percentage":41,"resets_at":1789466400}}}
JSON
```

## Project layout

- `Sources/AgentMonitorCore/UsageCache.swift` decodes status-line JSON and owns
  the cache format.
- `Sources/AgentMonitorBridge/main.swift` installs the integration, writes the
  cache, and preserves an existing status line.
- `Sources/AgentMonitorCore/ClaudeOAuthUsage.swift` reads the Keychain session,
  fetches usage, and decodes OAuth responses.
- `Sources/AgentMonitorCore/UsagePollingPolicy.swift` owns adaptive intervals,
  power-dependent minimums, and persistent endpoint cooldowns.
- `Sources/AgentMonitor/UsageStore.swift` coordinates cache events, polling,
  sleep/power notifications, and menu-bar state.
- `Sources/AgentMonitorCore/CodexUsage.swift` and `CodexUsageReader.swift` model
  Codex windows and read the freshest snapshot from `~/.codex/sessions` rollout logs.
- `Sources/AgentMonitor/CodexStore.swift` owns Codex menu-bar state.
- `Sources/AgentMonitor/MenuBarView.swift` is the popover: per-provider limit
  meters, menu-style commands (⌘R refresh, ⌘, settings, ⌘Q quit), and in-place
  settings and details panes (`MenuBarSettingsView.swift`,
  `ProviderDetailsView.swift`), built from `PopoverComponents.swift`.
- `Sources/AgentMonitor/StatusItemController.swift` uses Golden Gate's
  `NSStatusItemExpandedInterfaceDelegate` for menu tracking, keyboard navigation
  and selection highlighting. The glass panel sits directly beneath the status
  button and resizes from its top edge when switching panes. Explicit sizing
  avoids the stale backdrop and shadow observed with `MenuBarExtra(.window)`;
  there is no fallback styling for older macOS versions.
- `Sources/AgentMonitor/MenuBarIcon.swift` draws the menu-bar label: a bar pair
  per provider (Claude above, Codex below once it has data), top = short window,
  bottom = weekly, fill = remaining. Missing windows draw dotted; 90%+ adds an amber dot.
  `ProviderLogo.swift` draws the Anthropic/OpenAI marks from embedded SVG path data
  at the pair's height. `MenuBarStyle.swift` holds the options (`menuBar.*`
  UserDefaults keys) edited in `MenuBarSettingsView.swift` via Settings… in the popover.
- `Sources/MonitorCheck` contains deterministic decoding, cache, countdown,
  polling, credential, and intercepted HTTP checks. Normal checks never read
  credentials or call the live endpoint. `swift run MonitorCheck codex-live`
  reads real Codex logs.
