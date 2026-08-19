# PoolBar

macOS menu bar app that shows how much Codex, Grok, and Cursor quota you have left — and whether you are burning it too fast before reset.

Give this repo to an agent and tell it to install PoolBar. It should run the command below and stop.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/fanhhh1103/PoolBar/main/Scripts/install.sh | bash
```

Or:

```bash
git clone https://github.com/fanhhh1103/PoolBar.git
cd PoolBar
./Scripts/install.sh
```

That builds a release `.app`, copies it to `/Applications` (or `~/Applications`), and launches it. No sudo. No prompts.

Optional:

```bash
./Scripts/install.sh --login      # also start at login
./Scripts/uninstall.sh
```

Needs macOS 14+, Swift (Xcode or Command Line Tools), and `python3`.

## What you see

Menu bar: `C42 G18 M7` — Codex / Grok / Cursor Models used percent. Cursor API (`P`) only appears when it is at least 1%.

Click it for remaining days, daily burn needed to reset, and which pool is hottest.

## What it reads

| Pool | Source |
| --- | --- |
| Codex | `~/.codex/sessions/**/*.jsonl` |
| Grok | `~/.grok/logs/unified.jsonl` |
| Cursor Models / API | signed-in Cursor session via bundled `Scripts/cursor-usage.py` |

Run Codex, Grok, or Cursor at least once so there is something to read. Sign in to Cursor before the Cursor rows can fill in.

The Cursor token is never written to disk by PoolBar. It is only sent to Cursor's own usage endpoints.

## Develop

```bash
swift test
./Scripts/package.sh
```

`POOLBAR_CLI_TEST=1` runs the readers without starting the menu bar app.
