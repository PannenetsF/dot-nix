#!/usr/bin/env bash
# herdr-projects launcher (1.2.x board model): fzf over the registered repos,
# then open the chosen one's project coordinator: focus its live pane, restart
# the conversation when its pane is gone, or start a fresh coordinator on
# first use. Bound to prefix+ctrl+p as a herdr type="popup" command.
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
# Pre-check in the outer shell (not inside the picker's command substitution,
# where die could only kill the subshell).
[ -n "$(hp_list_known_repos)" ] || die "no registered repos yet (use prefix+shift+c to register one)"

repo="$(hp_pick_known_repo 'open repo > ')" || exit 0
[ -n "$repo" ] || exit 0

hp_open_repo_coordinator "$hp_bin" "$repo" || die "could not open the $repo coordinator (is herdr running?)"
