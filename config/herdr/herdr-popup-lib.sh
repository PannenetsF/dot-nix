#!/usr/bin/env bash
# Shared preamble for the five herdr popup launchers (new-project, pick-project,
# add-repo, new-coordinator, focus-coordinator). Each script sources the
# sibling copy of this file next to it (see the inline resolution block in each
# launcher); it must not be relied on to live anywhere on PATH. It deliberately
# does NOT enable `set -euo pipefail` itself: the sourcing script owns its own
# options, and this file must behave identically whether or not the caller set
# them.
#
# Bash 3.2-safe (macOS ships 3.2): no readarray/mapfile, no readlink -f/realpath.

# Popups close the moment the launcher script exits, so a bare error would
# flash by.
die() {
  printf '\nERROR: %s\n' "$1" >&2
  printf 'press enter to close' >&2
  read -r _ || true
  exit 1
}

# herdr runs popups with a bare launchd PATH: fzf lives in the nix profile
# (/etc/profiles/per-user/<user>/bin) and git may come from homebrew, none of
# which a bare launchd PATH includes. Prepend the usual install folders before
# any dependency check so the popup works regardless of how it was launched.
herdr_popup_prepend_path() {
  for dir in \
    "$HOME/.local/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.nix-profile/bin" \
    "/etc/profiles/per-user/${USER:-$(id -un)}/bin" \
    "/opt/homebrew/bin" \
    "/usr/local/bin"
  do
    [ -d "$dir" ] && PATH="$dir:$PATH"
  done
  export PATH
}

# Echo the resolved herdr-projects binary, or nothing if it cannot be found:
# $HERDR_PROJECTS_BIN when executable, else the per-user ~/.local/bin install,
# else whatever `command -v` finds on the (already prepended) PATH. Callers
# keep their own not-found handling (plain exit vs die) and wording.
herdr_projects_bin() {
  if [ -n "${HERDR_PROJECTS_BIN:-}" ] && [ -x "$HERDR_PROJECTS_BIN" ]; then
    printf '%s\n' "$HERDR_PROJECTS_BIN"
  elif [ -x "$HOME/.local/bin/herdr-projects" ]; then
    printf '%s\n' "$HOME/.local/bin/herdr-projects"
  else
    command -v herdr-projects 2>/dev/null || true
  fi
}

# --- Registered coordinator identity (fork pf.2) -----------------------------
#
# Coordinator identity is the agent NAME, not the working directory: only
# `hpc-<slug>` / `hpc-<slug>-N` agents count. The helpers below mirror the
# Rust names.rs exactly so the launchers decide the same way the plugin does.

# The pane a popup was launched for ("underlying tiled pane"); empty outside
# a popup (e.g. the script run straight from a shell).
hp_active_pane() {
  printf '%s\n' "${HERDR_ACTIVE_PANE_ID:-}"
}

# Mirror Rust `head(slug, n)`: the first n chars (slugs are ASCII), trailing
# hyphens trimmed. `hpc-<head24>` / `hpc-<head22>-N` are the two name widths.
hp_slug_head() {
  local slug="$1" n="$2" s
  s="${slug:0:$n}"
  while [ "${s: -1}" = "-" ]; do s="${s%?}"; done
  printf '%s\n' "$s"
}

# Cached `herdr agent list` JSON for this launcher run; empty on any failure.
hp_agent_list_json() {
  if [ -z "${_hp_agent_list_fetched:-}" ]; then
    _hp_agent_list="$(herdr agent list 2>/dev/null || true)"
    _hp_agent_list_fetched=1
  fi
  printf '%s' "$_hp_agent_list"
}

# Echo the registered agent name of a live pane (one line; empty when unnamed,
# absent, or without jq).
hp_agent_name_for_pane() {
  local pane="$1"
  command -v jq >/dev/null 2>&1 || return 0
  hp_agent_list_json | jq -r --arg p "$pane" \
    '.result.agents[]? | select(.pane_id == $p) | (.name // "")' 2>/dev/null | head -1
}

# Echo the cwd (fallback foreground_cwd) of a live pane, one line.
hp_pane_cwd() {
  local pane="$1" cwd
  command -v jq >/dev/null 2>&1 || return 0
  cwd="$(hp_agent_list_json | jq -r --arg p "$pane" \
    '.result.agents[]? | select(.pane_id == $p) | [.cwd, .foreground_cwd] | map(select(. != null and . != "")) | .[0] // ""' 2>/dev/null | head -1)"
  printf '%s\n' "$cwd"
}

# True when `name` is a registered coordinator name of `slug`: exactly
# `hpc-<head24>` or `hpc-<head22>-N` with N >= 1. Structural equality, never a
# prefix match (mirrors names::is_coordinator_name).
hp_pane_is_coordinator_of() {
  local slug="$1" name="$2" tail
  [ "$name" = "hpc-$(hp_slug_head "$slug" 24)" ] && return 0
  tail="hpc-$(hp_slug_head "$slug" 22)-"
  case "$name" in
    "$tail"*)
      local n="${name#"$tail"}"
      case "$n" in ''|*[!0-9]*) return 1 ;; esac
      [ "$n" -ge 1 ] 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# True when `name` is a registered thread name of `slug`: `hp-<head21>-t-NNNN`.
hp_pane_is_thread_of() {
  local slug="$1" name="$2" head
  head="hp-$(hp_slug_head "$slug" 21)-t-"
  case "$name" in "$head"*) return 0 ;; *) return 1 ;; esac
}

# Resolve the project slug for the current context: cwd directly under the
# projects root, then the active pane's hp_project token, then its cwd, then an
# fzf picker. Echoes the slug and returns 0; on fzf cancel echoes nothing and
# returns 1. Args: <hp_bin> <hp_root>.
hp_resolve_project_slug() {
  local hp_bin="$1" hp_root="$2" slug pane pane_json cwd projects selection

  hp_valid_slug() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; }

  case "$PWD/" in
    "$hp_root"/*)
      slug="${PWD#"$hp_root"/}"
      case "$slug" in */*) : ;; *) hp_valid_slug "$slug" && { printf '%s\n' "$slug"; return 0; } ;; esac
      ;;
  esac

  pane="$(hp_active_pane)"
  if [ -n "$pane" ] && command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    pane_json="$(herdr pane get "$pane" 2>/dev/null || true)"
    if [ -n "$pane_json" ]; then
      slug="$(printf '%s' "$pane_json" | jq -r '.result.pane.tokens.hp_project // empty' 2>/dev/null || true)"
      if hp_valid_slug "$slug"; then printf '%s\n' "$slug"; return 0; fi
      cwd="$(printf '%s' "$pane_json" | jq -r '.result.pane.cwd // empty' 2>/dev/null || true)"
      if [ -n "$cwd" ]; then
        case "$cwd/" in
          "$hp_root"/*)
            slug="${cwd#"$hp_root"/}"
            case "$slug" in */*) : ;; *) hp_valid_slug "$slug" && { printf '%s\n' "$slug"; return 0; } ;; esac
            ;;
        esac
      fi
    fi
  fi

  command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"
  projects="$("$hp_bin" --root "$hp_root" list 2>/dev/null)" || die "'herdr-projects list' failed"
  [ -n "$projects" ] || die "no projects under $hp_root yet (use prefix+shift+c to create one)"
  selection="$(printf '%s\n' "$projects" | fzf \
    --prompt='project > ' \
    --header='Esc: cancel')" || return 1
  [ -n "$selection" ] || return 1
  slug="${selection%%$'\t'*}"
  hp_valid_slug "$slug" || die "unexpected project list output: $selection"
  printf '%s\n' "$slug"
}

# Run `coordinator adopt --pane` in the FOREGROUND. It must not be detached:
# the popup command is its pty's foreground process group and Herdr kills that
# group on popup close, so `nohup ... &` never survives the teardown (nohup
# only ignores SIGHUP). Mirrors pick-project's foreground `open`. The live
# herdr socket is passed through explicitly in case the project has no recorded
# session yet; output is mirrored to a log.
# Args: <hp_bin> <hp_root> <slug> <pane>
hp_adopt() {
  local hp_bin="$1" hp_root="$2" slug="$3" pane="$4" log
  log="${TMPDIR:-/tmp}/herdr-adopt-coordinator-$slug.log"
  env HERDR_SOCKET_PATH="${HERDR_SOCKET_PATH:-}" \
    "$hp_bin" --root "$hp_root" coordinator adopt "$slug" --pane "$pane" 2>&1 | tee "$log"
}
