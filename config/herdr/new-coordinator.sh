#!/usr/bin/env bash
# herdr-projects launcher: open another coordinator for the current project,
# or register the pane underneath the popup when it is an unregistered agent
# sitting in the project home (the "stray session" case). Slug resolution
# order: cwd inside the projects root, the underlying tiled pane
# (HERDR_ACTIVE_PANE_ID in popups), then an fzf picker.
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

hp_bin="$(herdr_projects_bin)"
[ -n "$hp_bin" ] || die "herdr-projects binary not found"
hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"

# `open --new --tab`: another coordinator in a new tab. `open` polls for the
# new tab's shell to be ready (up to ~10s, usually a few). It MUST run in the
# FOREGROUND: a popup command runs as the pty's foreground process group, and
# Herdr kills that whole group when the popup pane closes, so `nohup … &` does
# NOT survive the teardown (nohup only ignores SIGHUP) — the coordinator never
# started and the launcher looked dead. Keeping the popup alive until `open`
# returns (same pattern as pick-project) lets the socket call finish; the
# output is mirrored to a log for troubleshooting.
open_new() {
  local slug="$1" log
  log="${TMPDIR:-/tmp}/herdr-new-coordinator-$slug.log"
  "$hp_bin" --root "$hp_root" open "$slug" --new --tab 2>&1 | tee "$log"
}

slug="$(hp_resolve_project_slug "$hp_bin" "$hp_root")" || exit 0
[ -n "$slug" ] || exit 0

# Identity check on the pane the popup was launched from. Coordinator
# identity is the registered NAME (fork pf.2): an unnamed agent whose cwd is
# the project home is NOT a coordinator yet — opening another one would stack
# a second hpc-<slug> beside the stray session that actually wants the role,
# so register that pane in place instead. A registered coordinator/thread, a
# subfolder guest, a stranger-named pane, or a plain-shell invocation (no
# active pane) all keep the old "open another coordinator" behavior.
pane="$(hp_active_pane)"
if [ -n "$pane" ]; then
  name="$(hp_agent_name_for_pane "$pane")"
  if [ -z "$name" ]; then
    pane_cwd="$(hp_pane_cwd "$pane")"
    case "$pane_cwd" in
      "$hp_root/$slug"|"$hp_root/$slug"/)
        hp_adopt "$hp_bin" "$hp_root" "$slug" "$pane"
        exit 0
        ;;
    esac
  fi
fi

open_new "$slug"
