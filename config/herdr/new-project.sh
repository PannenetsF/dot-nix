#!/usr/bin/env bash
# herdr-projects launcher: pick one or more local git repositories with fzf,
# then create (or open) the herdr-projects project attached to them. Bound to
# prefix+shift+c as a herdr type="popup" command, so it has an interactive TTY.
#
# Repository roots (colon-separated): HP_PROJECT_ROOTS, default
# ~/Documents/workspace. Repos up to 4 levels deep.
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

# --multi: Tab marks extra repos, Enter takes what is marked (or just the
# highlighted line for a single-repo project).
selection="$(list_repos | sort -u | fzf \
  --multi \
  --prompt='repos for new project > ' \
  --header='Enter: use selected (or highlighted) repo(s)   Tab: mark another   Esc: cancel')" || exit 0

[ -n "$selection" ] || exit 0
repos=()
while IFS= read -r line; do
  [ -n "$line" ] && repos+=("$line")
done <<< "$selection"
[ "${#repos[@]}" -gt 0 ] || die "no repo selected"
for repo in "${repos[@]}"; do
  [ -d "$repo" ] || die "selected path is not a directory: $repo"
done
first_repo="${repos[0]}"

default_slug="$(basename "$first_repo")"
printf 'Project slug (used in ~/.herdr-projects; default: %s): ' "$default_slug"
read -r slug
slug="${slug:-$default_slug}"
if ! printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
  die "invalid slug '$slug': use lowercase letters, digits and dashes"
fi

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"
if [ -d "$hp_root/$slug" ]; then
  echo "project '$slug' already exists; attaching any missing repos and opening it"
  for repo in "${repos[@]}"; do
    "$hp_bin" --root "$hp_root" set "$slug" repos.add "$repo" || die "'set repos.add $repo' failed"
  done
else
  repo_args=()
  for repo in "${repos[@]}"; do
    repo_args+=(--repo "$repo")
  done
  "$hp_bin" --root "$hp_root" new "$slug" "${repo_args[@]}" \
    || die "'new' failed for '$slug'"
fi

# Always open in the project's own workspace tab: from a popup pane plain
# `open` would start the coordinator in the transient pane, which closes the
# moment this script exits. Outside Herdr --tab behaves like plain open.
"$hp_bin" --root "$hp_root" open "$slug" --tab || die "'open' failed for '$slug'"
