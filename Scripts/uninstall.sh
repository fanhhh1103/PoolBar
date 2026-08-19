#!/usr/bin/env bash
# Remove PoolBar. Safe for agents: no prompts.
set -euo pipefail

if pgrep -x PoolBar >/dev/null 2>&1; then
  pkill -x PoolBar || true
  sleep 0.3
fi

removed=0
for dest in /Applications/PoolBar.app "$HOME/Applications/PoolBar.app"; do
  if [[ -d "$dest" ]]; then
    rm -rf "$dest"
    echo "removed $dest"
    removed=1
  fi
done

osascript -e 'tell application "System Events" to delete (every login item whose name is "PoolBar")' >/dev/null 2>&1 || true

if [[ "$removed" -eq 0 ]]; then
  echo "PoolBar.app was not installed"
else
  echo "done"
fi
