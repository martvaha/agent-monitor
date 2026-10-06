# Agent Monitor

macOS menu-bar app showing Claude Code and Codex usage. Details and design notes:
`docs/DETAILS.md`.

## Rules

- To get provider usage, read files the agent already writes or make a direct
  HTTP request to the provider's usage endpoint. Never launch the `claude` or
  `codex` CLI or scrape its TUI through a PTY; it is far too heavy. Never refresh
  or rewrite the agent's credentials. See "Data-source policy" in `docs/DETAILS.md`.

## Verify

```sh
swift build
swift run MonitorCheck
```

SwiftPM uses `sandbox-exec`, so these fail inside a sandboxed shell.
