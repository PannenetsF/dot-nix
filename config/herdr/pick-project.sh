#!/usr/bin/env bash
# herdr-projects launcher: fzf over existing projects, then open the chosen
# one. Bound to prefix+ctrl+p as a herdr type="popup" command.
#
# Why a script and not the plugin's `open` action: that action opens the
# *current workspace's* project directly when invoked inside one, and only
# shows a picker outside project workspaces. This always asks.
set -euo pipefail

hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
[ -x "$hp_bin" ] || hp_bin="$(command -v herdr-projects 2>/dev/null || true)"
if [ -z "$hp_bin" ]; then
  echo "herdr-projects binary not found" >&2
  exit 1
fi
command -v fzf >/dev/null 2>&1 || { echo "fzf not found on PATH" >&2; exit 1; }

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"

# `list` lines: slug, status and a thread summary (tab-separated). Archived
# projects stay out of the switcher.
selection="$("$hp_bin" --root "$hp_root" list 2>/dev/null | fzf \
  --prompt='open project > ' \
  --header='Enter: open/focus coordinator   Esc: cancel')" || exit 0

[ -n "$selection" ] || exit 0
slug="${selection%%$'\t'*}"
[ -n "$slug" ] || exit 0

# In a plugin popup pane this opens the coordinator in the project's own
# workspace tab; outside Herdr it starts in the current pane.
exec "$hp_bin" --root "$hp_root" open "$slug"
