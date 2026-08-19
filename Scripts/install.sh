#!/usr/bin/env bash
# PoolBar installer. Safe for agents: no prompts, no sudo, no Simulator.
set -euo pipefail

REPO_URL="${POOLBAR_REPO:-https://github.com/fanhhh1103/PoolBar.git}"
SRC_DIR="${POOLBAR_SRC:-$HOME/.poolbar/src}"
ADD_LOGIN=0
NO_LAUNCH=0
RUN_TESTS=0

usage() {
  cat <<'EOF'
Install PoolBar into /Applications (or ~/Applications) and launch it.

Usage: install.sh [--login] [--no-launch] [--test]

  --login      also add a Login Item so it starts at boot
  --no-launch  install only, do not open the app
  --test       run `swift test` before packaging
EOF
}

for arg in "$@"; do
  case "$arg" in
    --login) ADD_LOGIN=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --test) RUN_TESTS=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "unknown flag: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "PoolBar is a macOS menu bar app. This machine is $(uname -s)." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift not found. Install Xcode or the Command Line Tools, then retry:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found. macOS should ship one; install Xcode CLT if missing." >&2
  exit 1
fi

script_path="${BASH_SOURCE[0]:-}"
root=""
if [[ -n "$script_path" && -f "$script_path" && "$script_path" != /dev/fd/* ]]; then
  here="$(cd "$(dirname "$script_path")" && pwd)"
  if [[ -f "$here/../Package.swift" ]]; then
    root="$(cd "$here/.." && pwd)"
  fi
fi

if [[ -z "$root" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "git not found, and this script is not running from a clone." >&2
    exit 1
  fi
  if [[ -f "$SRC_DIR/Package.swift" ]]; then
    echo "updating $SRC_DIR"
    git -C "$SRC_DIR" pull --ff-only
  else
    echo "cloning $REPO_URL -> $SRC_DIR"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 "$REPO_URL" "$SRC_DIR"
  fi
  root="$SRC_DIR"
fi

cd "$root"
echo "source: $root"

if [[ "$RUN_TESTS" -eq 1 ]]; then
  swift test
fi

bash "$root/Scripts/package.sh"

dest="/Applications/PoolBar.app"
if [[ ! -w /Applications ]]; then
  mkdir -p "$HOME/Applications"
  dest="$HOME/Applications/PoolBar.app"
fi

if pgrep -x PoolBar >/dev/null 2>&1; then
  echo "stopping running PoolBar"
  pkill -x PoolBar || true
  sleep 0.4
fi

rm -rf "$dest"
ditto "$root/PoolBar.app" "$dest"
echo "installed: $dest"

if [[ "$ADD_LOGIN" -eq 1 ]]; then
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$dest\", hidden:true}" >/dev/null
  echo "login item added"
fi

if [[ "$NO_LAUNCH" -eq 0 ]]; then
  open "$dest"
  sleep 1
  if pgrep -x PoolBar >/dev/null 2>&1; then
    echo "PoolBar is running. Look at the menu bar for C / G / M percentages."
  else
    echo "App was opened but the process is not visible yet. Check the menu bar, or:" >&2
    echo "  open \"$dest\"" >&2
  fi
fi

echo "done"
