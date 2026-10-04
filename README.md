# Agent Monitor

A small Mac app that lives in the menu bar (top right of your screen).
It shows how much of your Claude and Codex usage limits you have used, and when they reset.

<p align="center">
  <img src="docs/screenshot.png" alt="Agent Monitor menu bar overlay" width="420">
</p>

## What you see

- **Menu bar bars**: two slim bars for Claude (top: 5-hour, bottom: weekly), plus
  a second pair beneath for Codex once it has data. Fill shows how much is left (bars shrink as you use more);
  a dotted bar means that limit is unavailable, and an amber dot marks 90%+.
  Each pair starts with a small provider logo. Choose Settings… (⌘,) in the popover to
  pick providers, bars, colours, fill direction, logos, and the warning level
- **5-hour limit**: how much you used in the last 5 hours
- **Weekly limit**: how much you used this week
- **Reset timer**: how long until each limit resets
- **Codex usage** (optional): same idea, for OpenAI Codex, if you use it

## How it works

The app reads your existing Claude Code sign-in from the Mac Keychain and checks
Claude’s usage endpoint. This works with Claude Code in **Zed**, without opening
the terminal CLI. One request retrieves both the 5-hour and weekly limits.

Checks adapt to activity and power:

| Mac power state | Active usage | Idle |
| --- | --- | --- |
| Plugged in | Every 2 minutes | Gradually slows to every 15 minutes |
| Battery | Every 5 minutes | Gradually slows to every 30 minutes |
| Low Power Mode | Every 10 minutes | Gradually slows to every hour |

Opening the menu brings the next check forward when allowed. The app pauses
during sleep and backs off after errors or rate limits, honoring server cooldowns.
Local Claude session-file changes also bring polling forward, using native
notifications batched over one minute. If those files are unavailable, or usage
comes from another device, detection can take up to the idle interval. Opening the
menu checks sooner, subject to the minimum interval and any cooldown.

For terminal Claude Code, the included status-line helper also saves usage after
each answer. The app watches that file for immediate updates and postpones its
next network check when it receives fresh local usage.

For Codex, the app reads the log files Codex already writes on your Mac.

## Good to know

- Claude usage checks use the internet and include changes from other devices.
- Session tokens are sent only to Anthropic and are never saved in the app’s cache.
- The app uses the existing sign-in; Claude Code handles renewing it. If it expires,
  use Claude Code in Zed again. Background checks never open permission dialogs.
- If access is needed, click **Allow Keychain access** in the menu, enter your Mac
  login Keychain password, and choose **Always Allow**. Touch ID cannot replace
  this password prompt for Claude Code’s existing login Keychain item.
- When a check fails, the app keeps the last reading and shows its update time.
- If you already have your own status line in Claude Code, it still works.
  The helper passes the data on to it.

## What you need

- macOS 27 (Golden Gate)
- Claude Code 2.1.80 or newer
- A Claude Pro or Max subscription

## Install

```sh
./scripts/make-app.sh --install
```

This builds the app, puts it in `~/Applications`, sets up the helper and starts the app.
Local builds reuse a signing identity in the ignored `.local-signing` directory,
so rebuilding preserves **Always Allow**. Keep that directory between builds.

Agent Monitor keeps the existing bundle identifier, cache directory, and
`CLAUDE_MONITOR_*` environment variables for compatibility with earlier installs.
Installing it updates an existing Claude Monitor status-line helper automatically.

## Uninstall the helper

```sh
~/Applications/AgentMonitor.app/Contents/Helpers/AgentMonitorBridge --uninstall
```

This puts your old Claude Code status line back.

## More details

See [docs/DETAILS.md](docs/DETAILS.md) for the technical explanation.
