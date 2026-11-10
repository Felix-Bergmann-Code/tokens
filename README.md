<div align="center">

# Tokens

**See how many tokens your coding agents burn, and what that's worth at API prices.**
A minimalist macOS menu bar companion for Claude Code and Codex.

[![Build](https://github.com/Felix-Bergmann-Code/tokens/actions/workflows/build.yml/badge.svg)](https://github.com/Felix-Bergmann-Code/tokens/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Website](https://felix-bergmann-code.github.io/tokens/) · [Contributing](CONTRIBUTING.md) · Sister apps: [Gauge](https://github.com/Felix-Bergmann-Code/gauge), [Isle](https://github.com/Felix-Bergmann-Code/isle)

</div>

---

Tokens reads the session logs that Claude Code and Codex already write to your disk and turns them into a live dashboard in your menu bar. **Everything stays on your Mac: no network requests, no account, no telemetry, no dependencies.**

## Features

- **Overview**: tokens and API-equivalent cost for today, 7 days, 30 days or all time. It has hourly, daily and weekly charts, a per-agent breakdown (terminal, desktop app, SDK, IDE), top models and insights.
- **Months**: monthly totals, a 20-week activity heatmap and each month's value compared with what your plans cost.
- **Plans**: how much value you get from your Claude and ChatGPT subscriptions (API value ÷ plan price), when each one breaks even, your effective cost per 1M tokens, and live Codex rate-limit gauges for the 5-hour and weekly windows.
- **Live**: the app watches the log folders with FSEvents and updates about a second after an agent writes.
- **Menu bar**: shows today's tokens, today's API value or just an icon. Launch at Login is built in.

## Install

Build from source (takes about a minute):

```bash
git clone https://github.com/Felix-Bergmann-Code/tokens.git
cd tokens
./scripts/build.sh --install   # builds, copies to ~/Applications and launches
```

Requires **macOS 26+** (Liquid Glass) and **Xcode 26+**. Drop `--install` to build into `./build/Tokens.app` without installing it.

## Where the numbers come from

| Agent | Read from |
|---|---|
| Claude Code (terminal, desktop app, Agent SDK) | `~/.claude/projects/**/*.jsonl` (respects `CLAUDE_CONFIG_DIR`) |
| Codex (desktop app, CLI, IDE extension) | `~/.codex/sessions`, `~/.codex/archived_sessions` (respects `CODEX_HOME`) |

- **Plans** are detected automatically. Claude's comes from the rate-limit tier in `~/.claude.json` (only that field and the subscription date are read). ChatGPT's comes from the Codex rate-limit events. You can override both in settings.
- **Prices** are API list rates as of Oct 2026 and live in [`Sources/Tokens/Pricing.swift`](Sources/Tokens/Pricing.swift). Cache reads and writes are priced separately. Anthropic charges 1.25× input for 5-minute cache writes and 2× for 1-hour writes.
- **Speed**: logs are append-only, so after the first scan only new lines are parsed. Per-file results are cached in `~/Library/Application Support/Tokens/`.

The cost shown is what the same usage *would* cost at API prices, not what you are billed.

## Command line

```bash
.build/release/Tokens --dump [--rebuild]   # print a daily summary to stdout
.build/release/Tokens --snapshot <dir>     # render each tab to PNG (light + dark)
```

## Contributing

PRs are very welcome! Some of the most useful contributions:

> 💸 **Keep prices current.** Model prices change often. If a model is missing or a rate is out of date, update [`Pricing.swift`](Sources/Tokens/Pricing.swift) and link the official pricing page in your PR.

- **More agents**: Gemini CLI, Cursor, Aider, OpenCode, or anything else that writes usage logs locally.
- **Log format changes**: if Claude Code or Codex change their log format and numbers look wrong, `Tokens --dump --rebuild` helps narrow it down.
- **Export** (CSV/JSON), notifications for usage spikes, an older-macOS fallback without Liquid Glass.

Read [CONTRIBUTING.md](CONTRIBUTING.md) to get set up, and please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Project layout

```
Sources/Tokens/
  TokensApp.swift      app entry, menu bar label, --dump
  Scanner.swift        log discovery, incremental JSONL parsing, cache
  FolderWatcher.swift  FSEvents watcher
  Store.swift          aggregation, periods, plans, insights
  Pricing.swift        API prices and subscription plans
  *View.swift          popover tabs and settings
  Snapshotter.swift    --snapshot renderer
scripts/               build.sh, make-icon.swift
docs/                  website (GitHub Pages)
```

## License

[MIT](LICENSE) © Felix Bergmann and contributors

Not affiliated with Anthropic or OpenAI. Claude, Claude Code, ChatGPT and Codex are trademarks of their respective owners.
