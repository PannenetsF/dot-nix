#!/usr/bin/env bash
# herdr-projects launcher (1.2.x board model): pick one or more local git
# checkouts with fzf, register them in the herdr-projects repo registry, and
# open the first repo's project coordinator (focus the live pane, or start it).
# Bound to prefix+shift+c as a herdr type="popup" command, so it has an
# interactive TTY.
#
# Repository roots (colon-separated): HP_PROJECT_ROOTS, default
# ~/Documents:~/.config. Repos up to 4 levels deep.
set -euo pipefail

# Locate and source the shared popup library. Resolve one symlink hop: Home
# Manager links ~/.local/bin/herdr-<name> at the nix-store file, whose own
# directory also holds the linked lib; run straight from the repo there is no
# symlink and the sibling sits on disk beside this script.
self="${BASH_SOURCE[0]}"
if target="$(readlink "$self" 2>/dev/null)" && [ -n "$target" ]; then self="$target"; fi
case "$self" in /*) ;; *) self="$(cd "$(dirname "$self")" 2>/dev/null && pwd)/$(basename "$self")" ;; esac
self_dir="$(cd "$(dirname "$self")" && pwd)"
# shellcheck source=/dev/null
. "$self_dir/herdr-popup-lib.sh"

herdr_popup_prepend_path
hp_export_env

hp_bin="$(herdr_projects_bin)"
if [ -z "$hp_bin" ]; then
  echo "herdr-projects binary not found" >&2
  exit 1
fi
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"

# fzf multi: Tab marks extra checkouts, Enter takes the marked ones (or just
# the highlighted line for a single repo).
selection="$(hp_scan_local_repos | sort -u | fzf \
  --multi \
  --prompt='register repo(s) > ' \
  --header='Enter: register selected (or highlighted) repo(s) and open the first   Tab: mark another   Esc: cancel')" || exit 0

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
for repo in "${repos[@]}"; do
  hp_register_repo "$hp_bin" "$repo" || die "failed to register $repo"
done
first_name="$(hp_known_repo_for_path "$first_repo")"
[ -n "$first_name" ] || die "the selected repo did not end up registered: $first_repo"

# Open the first repo's coordinator: jumps to its pane when it already runs,
# restarts the same conversation after a crash, or starts a fresh one. The CLI
# queues and lets its own detached pump open the tab, so the popup can close.
hp_open_repo_coordinator "$hp_bin" "$first_name" || die "could not open the $first_name coordinator (is herdr running?)"
