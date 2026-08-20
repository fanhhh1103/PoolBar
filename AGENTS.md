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

## Cursor Cloud specific instructions

Cloud Agent VMs are Linux, but PoolBar is a macOS-only menu bar app. The GUI executable (`Sources/PoolBar`, imports `SwiftUI`/`Combine`/`Security`), `Scripts/package.sh`/`install.sh` (`.app` bundle, `codesign`, `open`), and the live menu bar cannot build or run on Linux. Real GUI/`.app` verification and full CI happen on macOS (`.github/workflows/test.yml` runs `swift test` on `macos-15`). Do not try to launch the app here.

What the Linux VM can build/test:

- Swift 6 toolchain is installed via swiftly and persisted in the snapshot; `swift` is on `PATH` via `~/.profile` and `~/.bashrc`. The package has no external SPM dependencies.
- `swift build --target PoolBarCore` compiles the cross-platform core (`Sources/PoolBarCore/DailyBurn.swift`, Foundation only).
- Plain `swift test` FAILS on Linux because SwiftPM also compiles the macOS-only `PoolBar` executable target. To run the real `PoolBarTests`/`DailyBurnTests` here, copy `Sources/PoolBarCore` and `Tests/PoolBarTests` into a throwaway SwiftPM package that declares only the `PoolBarCore` library + `PoolBarTests` test target (no executable, no `platforms`), then run `swift test` there.
- `Scripts/cursor-usage.py` runs on Linux (`python3 -m py_compile` passes), but needs a signed-in macOS Cursor session for real data; on Linux `refresh --dry-run` exits 2 ("No Cursor session token found"), which is expected.
