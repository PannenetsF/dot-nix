#!/usr/bin/env bash
# herdr-projects launcher (1.2.x board model): register local git checkouts in
# the herdr-projects repo registry without attaching them to anything. fzf
# multi-picks checkouts under the scan roots; already-registered ones are
# filtered out. Registration never starts an agent (an undelegated placeholder
# task is created and removed at once; only data/repos.json persists).
# Bound to prefix+shift+a as a herdr type="popup" command.
#
# Roots: HP_PROJECT_ROOTS (colon-separated), default ~/Documents:~/.config.
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
[ -n "$hp_bin" ] || die "herdr-projects binary not found"
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"

# Hide checkouts already in the registry (compare real paths once). Kept as
# its own step (not in the fzf pipeline) so a python failure dies loudly
# instead of being masked by fzf's exit status.
candidates="$(hp_scan_local_repos | sort -u | hp_filter_unknown_repos)" \
  || die "failed to filter already-registered repos"

[ -n "$candidates" ] || die "every checkout under the scan roots is already registered"

selection="$(printf '%s\n' "$candidates" | fzf \
  --multi \
  --prompt='register repo(s) > ' \
  --header='Enter: register selected (or highlighted) repo(s)   Tab: mark another   Esc: cancel')" || exit 0
[ -n "$selection" ] || exit 0

repos=()
while IFS= read -r line; do
  [ -n "$line" ] && repos+=("$line")
done <<< "$selection"

n=0
for repo in "${repos[@]}"; do
  [ -d "$repo" ] || die "not a directory: $repo"
  if hp_register_repo "$hp_bin" "$repo"; then n=$((n + 1)); else die "failed to register $repo"; fi
done
printf '\n%d repo(s) registered\n' "$n"
printf 'press enter to close'
read -r _ || true
