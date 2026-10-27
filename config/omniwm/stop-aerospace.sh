#!/usr/bin/env bash
set -euo pipefail

# Run as the desktop user. Unload supervisors first so they cannot restart the
# old WM or its overlays while OmniWM is being tried.
uid="$(id -u)"
labels=(
  org.nix-community.home.aerospace-workspace-indicator
  org.nix-community.home.borders
  org.nix-community.home.aerospace
)
for label in "${labels[@]}"; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done

# bootout only stops the current registration: the plists are RunAtLoad, so
# leaving them on disk relights the whole stack at the next GUI login (this is
# how the indicator came back after the switch to OmniWM). Remove them; the
# apps/casks themselves stay installed for manual rollback (brew cleanup is
# disabled), only the login-time supervisors go away.
agents_dir="$HOME/Library/LaunchAgents"
for label in "${labels[@]}"; do
  rm -f "$agents_dir/$label.plist"
done

# Also cover instances launched outside our LaunchAgents. Use SIGTERM so
# AeroSpace gets a chance to restore its parked windows; never force-kill it.
for process in AeroSpace borders; do
  if pgrep -u "$uid" -x "$process" >/dev/null 2>&1; then
    pkill -TERM -u "$uid" -x "$process" || true
    for ((attempt = 0; attempt < 30; attempt++)); do
      if ! pgrep -u "$uid" -x "$process" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done
    if pgrep -u "$uid" -x "$process" >/dev/null 2>&1; then
      echo >&2 "[omniwm-trial] $process is still running; quit it before retrying activation."
      exit 1
    fi
  fi
done
