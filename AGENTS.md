# PoolBar

macOS menu bar quota meter for Codex, Grok, and Cursor. Not an iOS app. Do not open Simulator.app.

## Agent: install (no prompts)

User asked to install PoolBar. Run exactly this:

```bash
curl -fsSL https://raw.githubusercontent.com/fanhhh1103/PoolBar/main/Scripts/install.sh | bash
```

If curl-pipe is blocked, clone then install:

```bash
git clone https://github.com/fanhhh1103/PoolBar.git "$HOME/.poolbar/src"
"$HOME/.poolbar/src/Scripts/install.sh"
```

Need it at login: add `--login` to `install.sh`.
Uninstall: `Scripts/uninstall.sh`.

Success: `/Applications/PoolBar.app` or `~/Applications/PoolBar.app` exists, process `PoolBar` is running, menu bar shows `Cxx Gxx Mxx`.

If `swift` is missing: `xcode-select --install`. Do not invent a Homebrew cask. Requires macOS 14+ and `python3`.

## What

- Menu bar extra. Reads local Codex / Grok logs and the signed-in Cursor session.
- Tokens stay on this Mac. Cursor token is only sent to `api2.cursor.sh` / `cursor.com`.
- Canonical paths: `Sources/PoolBar`, `Sources/PoolBarCore`, `Scripts/install.sh`, `Scripts/cursor-usage.py`.

## Why

- Install must stay one non-interactive script. Do not split setup across manual clicks.
- Cursor usage must use the bundled script, not a private orchestration tree.

## How

On code changes:

1. `swift test`
2. `./Scripts/package.sh` then `./Scripts/install.sh --no-launch` if you need a local .app

Authority: this file → `README.md` → source.
