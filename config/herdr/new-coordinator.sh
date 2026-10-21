#!/usr/bin/env bash
# herdr-projects launcher (1.2.x board model): start a FRESH project
# coordinator conversation for the current repo. Repo resolution order: the
# shell cwd when it is inside a registered checkout, the underlying tiled pane
# (HERDR_ACTIVE_PANE_ID in popups), then an fzf picker over the registry. The
# CLI only queues "coordinator new" and kicks the plugin's own detached pump,
# which opens the coordinator's tab, so the popup closes immediately.
# Bound to prefix+ctrl+n in config/herdr/config.toml.
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

# A coordinator always belongs to a registered repo; pre-check here in the
# outer shell (the picker runs inside a command substitution below).
[ -n "$(hp_list_known_repos)" ] || die "no registered repos yet (use prefix+shift+c to register one)"

repo="$(hp_resolve_repo)" || exit 0
[ -n "$repo" ] || exit 0

# `new` always asks for a fresh conversation (same key as the board's own
# "new coordinator"); to re-enter the existing one without resetting it use
# prefix+ctrl+p / prefix+ctrl+f. Returns as soon as the request is queued.
msg="$("$hp_bin" coordinator --project "$repo" new 2>&1)" || {
  printf '%s\n' "$msg" >&2
  die "'coordinator new' failed for $repo (herdr running, and an agent program chosen?)"
}
printf '%s\n' "$msg"
