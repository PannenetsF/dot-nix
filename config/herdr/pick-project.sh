#!/usr/bin/env bash
# herdr-projects launcher: fzf over existing projects, then open the chosen
# one. Bound to prefix+ctrl+p as a herdr type="popup" command.
#
# Why a script and not the plugin's `open` action: that action opens the
# *current workspace's* project directly when invoked inside one, and only
# shows a picker outside project workspaces. This always asks.
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
# `list` is ours, so a slug outside the slug charset means the output shape
# changed (or something else is on the other end); fail loudly instead of
# feeding garbage to `open`.
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "unexpected project list output: $selection"

# Open the project in its own workspace tab: from a popup pane plain `open`
# would start the coordinator in the transient pane, which closes the moment
# this script exits. Outside Herdr --tab behaves like plain open.
#
# After a herdr restart the recorded socket is stale and `open` fails with a
# human-readable "... socket no longer exists ... pass --rebind ..." error.
# The plugin has no stable error code, so we match that text and retry once
# with --rebind; anything else is a real failure.
open_project() {
  local open_slug="$1" open_msg
  if open_msg="$("$hp_bin" --root "$hp_root" open "$open_slug" --tab 2>&1)"; then
    [ -n "$open_msg" ] && printf '%s\n' "$open_msg"
    return 0
  fi
  case "$open_msg" in
    *"no longer exists"*)
      printf '%s\n' "$open_msg" >&2
      echo "retrying with --rebind ..."
      if open_msg="$("$hp_bin" --root "$hp_root" open "$open_slug" --tab --rebind 2>&1)"; then
        [ -n "$open_msg" ] && printf '%s\n' "$open_msg"
        return 0
      fi
      ;;
  esac
  printf '%s\n' "$open_msg" >&2
  die "'open' failed for '$open_slug'"
}

open_project "$slug"
