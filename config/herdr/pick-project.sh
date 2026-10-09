#!/usr/bin/env bash
# herdr-projects launcher: fzf over existing projects, then open the chosen
# one. Bound to prefix+ctrl+p as a herdr type="popup" command.
#
# Why a script and not the plugin's `open` action: that action opens the
# *current workspace's* project directly when invoked inside one, and only
# shows a picker outside project workspaces. This always asks.
set -euo pipefail

# Popups close the moment this script exits, so a bare error would flash by.
die() {
  printf '\nERROR: %s\n' "$1" >&2
  printf 'press enter to close' >&2
  read -r _ || true
  exit 1
}

hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
[ -x "$hp_bin" ] || hp_bin="$(command -v herdr-projects 2>/dev/null || true)"
if [ -z "$hp_bin" ]; then
  echo "herdr-projects binary not found" >&2
  exit 1
fi
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"

# `list` lines: slug, status and a thread summary (tab-separated). Archived
# projects stay out of the switcher.
projects="$("$hp_bin" --root "$hp_root" list 2>/dev/null)" || die "'herdr-projects list' failed"
[ -n "$projects" ] || die "no projects under $hp_root yet (use prefix+shift+c to create one)"

selection="$(printf '%s\n' "$projects" | fzf \
  --prompt='open project > ' \
  --header='Enter: open/focus coordinator   Esc: cancel')" || exit 0

[ -n "$selection" ] || exit 0
slug="${selection%%$'\t'*}"
[ -n "$slug" ] || exit 0

# Always open in the project's own workspace tab: from a popup pane plain
# `open` would start the coordinator in the transient pane, which closes the
# moment this script exits. Outside Herdr --tab behaves like plain open.
"$hp_bin" --root "$hp_root" open "$slug" --tab || die "'open' failed for '$slug'"
