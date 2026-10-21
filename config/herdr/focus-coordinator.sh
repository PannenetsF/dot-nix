#!/usr/bin/env bash
# herdr-projects launcher (1.2.x board model): jump the client to a repo's
# project coordinator WITHOUT starting one. The recorded pane in the
# coordinator's state.json wins (across herdr sessions — its socket is pinned
# in the state and exported for the focus call); if that pane is gone, any
# live agent still carrying the sw-coordinator-<repo> name (or its -2/-3
# disambiguation) at the repo root is used, newest activity first.
#
# The plugin ships no per-repo equivalent of its top-level open-coordinator
# action, so this is and stays a shell feature. Repo resolution order: the
# shell cwd / the underlying tiled pane, then fzf over repos that actually have
# coordinator state. Bound to prefix+ctrl+f in config/herdr/config.toml.
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

repo="$(hp_known_repo_for_path "$PWD")"
if [ -z "$repo" ]; then
  pane="$(hp_active_pane)"
  if [ -n "$pane" ]; then
    dir="$(hp_pane_cwd "$(hp_current_socket)" "$pane")"
    [ -n "$dir" ] && repo="$(hp_known_repo_for_path "$dir")"
  fi
fi
if [ -z "$repo" ]; then
  command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"
  state_repos="$(hp_state_repos)"
  [ -n "$state_repos" ] || die "no project coordinator has ever run here (start one with prefix+ctrl+n)"
  # Show the checkout path beside each name when known.
  selection="$(while IFS= read -r name; do
      path="$(hp_repo_path "$name")"
      printf '%s\t%s\n' "$name" "$path"
    done <<< "$state_repos" | fzf \
      --prompt='focus coordinator > ' \
      --header='Enter: jump to its pane   Esc: cancel')" || exit 0
  [ -n "$selection" ] || exit 0
  repo="${selection%%$'\t'*}"
  hp_valid_repo_name "$repo" || die "unexpected coordinator list output: $selection"
fi
[ -n "$repo" ] || exit 0

if [ "$(hp_focus_repo_coordinator "$repo")" = "focused" ]; then
  exit 0
fi

echo "no live coordinator for '$repo'."
echo "start a fresh one with prefix+ctrl+n, or reopen the conversation with prefix+ctrl+p."
printf 'press enter to close'
read -r _ || true
exit 1
