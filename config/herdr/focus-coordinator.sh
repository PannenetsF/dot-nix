#!/usr/bin/env bash
# herdr-projects launcher: jump the client to the project's registered
# coordinator. The primary comes from the project's coordinator.json; if that
# pane is gone, any live pane still carrying the hpc-<slug> family name is
# used. An unregistered agent sitting in the project home UNDER THE POPUP is
# adopted in place instead (same identity rule as prefix+ctrl+n). Slug
# resolution order: cwd, the underlying tiled pane, then an fzf picker.
# Bound to prefix+ctrl+f in config/herdr/config.toml.
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

slug="$(hp_resolve_project_slug "$hp_bin" "$hp_root")" || exit 0
[ -n "$slug" ] || exit 0
state_file="$hp_root/$slug/.state/coordinator.json"

# An unregistered root pane invoking this popup wants to BE the coordinator:
# register it in place, exactly like prefix+ctrl+n does.
pane="$(hp_active_pane)"
if [ -n "$pane" ]; then
  name="$(hp_agent_name_for_pane "$pane")"
  if [ -z "$name" ]; then
    pane_cwd="$(hp_pane_cwd "$pane")"
    case "$pane_cwd" in
      "$hp_root/$slug"|"$hp_root/$slug"/)
        hp_adopt_detached "$hp_bin" "$hp_root" "$slug" "$pane"
        echo "registering this pane as hpc-$(hp_slug_head "$slug" 24); run context there"
        exit 0
        ;;
    esac
  fi
fi

command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

# The recorded session wins; the CLI needs its socket explicitly when the
# popup runs in another herdr session.
record_socket="$(jq -r '.socket // empty' "$state_file" 2>/dev/null || true)"
record_pane="$(jq -r '.pane_id // empty' "$state_file" 2>/dev/null || true)"
if [ -n "$record_socket" ]; then
  export HERDR_SOCKET_PATH="$record_socket"
fi

agents_json="$(herdr agent list 2>/dev/null || true)"
[ -n "$agents_json" ] || die "the project's herdr session is not reachable"

# Candidate lines for family members in the project home:
# `<pane_id>\t<name>\t<state_change_seq>`, ordered by agent list. The family
# test runs once, in bash (hp_pane_is_coordinator_of), so the 24/22 truncation
# rule lives in the shared library and never gets re-implemented in jq.
candidates="$(printf '%s' "$agents_json" | jq -r --arg home "$hp_root/$slug" '
  .result.agents[]?
  | select((.cwd // "") == $home or (.foreground_cwd // "") == $home)
  | [.pane_id, (.name // ""), (.state_change_seq // 0)] | @tsv' 2>/dev/null || true)"

target=""
best_seq=-1
while IFS=$'\t' read -r cid cname cseq; do
  [ -n "$cid" ] || continue
  hp_pane_is_coordinator_of "$slug" "$cname" || continue
  if [ "$cid" = "$record_pane" ]; then
    target="$cid"
    break
  fi
  if [ "$cseq" -gt "$best_seq" ] 2>/dev/null; then
    best_seq="$cseq"
    target="$cid"
  fi
done <<EOF
$candidates
EOF

if [ -z "$target" ]; then
  echo "no registered coordinator for '$slug'."
  echo "open the pane that should coordinate it and press prefix+ctrl+n to register,"
  echo "or run: $hp_bin coordinator adopt $slug --pane <id>"
  printf 'press enter to close'
  read -r _ || true
  exit 1
fi

herdr agent focus "$target" || die "could not focus pane $target"
