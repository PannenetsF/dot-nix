#!/usr/bin/env bash
# herdr-projects launcher: pick a local git repository with fzf, then create
# (or open) the herdr-projects project attached to it. Bound to prefix+shift+c
# as a herdr type="popup" command, so it has an interactive TTY.
#
# Repository roots (colon-separated): HP_PROJECT_ROOTS, default
# ~/Documents/workspace. Repos up to 4 levels deep.
set -euo pipefail

hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
[ -x "$hp_bin" ] || hp_bin="$(command -v herdr-projects 2>/dev/null || true)"
if [ -z "$hp_bin" ]; then
  echo "herdr-projects binary not found" >&2
  exit 1
fi
command -v fzf >/dev/null 2>&1 || { echo "fzf not found on PATH" >&2; exit 1; }

roots="${HP_PROJECT_ROOTS:-$HOME/Documents/workspace}"

# Absolute repo paths, one per line (fuzzy match on the full path).
list_repos() {
  old_ifs=$IFS
  IFS=:
  for root in $roots; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 4 -type d -name .git -prune 2>/dev/null |
      while IFS= read -r gitdir; do
        printf '%s\n' "${gitdir%/.git}"
      done
  done
  IFS=$old_ifs
}

selection="$(list_repos | sort -u | fzf \
  --prompt='repo for new project > ' \
  --header='Enter: create/open project on this repo   Esc: cancel')" || exit 0

[ -n "$selection" ] || exit 0
repo="$selection"
[ -d "$repo" ] || exit 0

default_slug="$(basename "$repo")"
printf 'Project slug (used in ~/.herdr-projects; default: %s): ' "$default_slug"
read -r slug
slug="${slug:-$default_slug}"
if ! printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
  echo "invalid slug: use lowercase letters, digits and dashes" >&2
  exit 1
fi

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"
if [ -d "$hp_root/$slug" ]; then
  echo "project '$slug' already exists; attaching this repo if needed and opening it"
  "$hp_bin" set "$slug" repos.add "$repo" >/dev/null 2>&1 || true
else
  "$hp_bin" --root "$hp_root" new "$slug" --repo "$repo"
fi

# Always open in the project's own workspace tab: from a popup pane plain
# `open` would start the coordinator in the transient pane, which closes the
# moment this script exits. Outside Herdr --tab behaves like plain open.
exec "$hp_bin" --root "$hp_root" open "$slug" --tab
