#!/usr/bin/env bash
# herdr-projects launcher: open another coordinator for the current project.
# Slug resolution order: cwd inside the projects root, the underlying tiled
# pane (HERDR_ACTIVE_PANE_ID in popups), then an fzf picker.
# Bound to prefix+ctrl+n in config/herdr/config.toml.
set -euo pipefail

# Popups close the moment this script exits, so a bare error would flash by.
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

hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
[ -x "$hp_bin" ] || hp_bin="$(command -v herdr-projects 2>/dev/null || true)"
[ -n "$hp_bin" ] || die "herdr-projects binary not found"
hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"

valid_slug() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]]; }

# `open --new --tab`: another coordinator in a new tab. `open` itself polls
# for the new tab's shell to be ready (up to ~10s, usually a few), which would
# keep the popup open that whole time. Run it detached so the popup closes now;
# the coordinator primes itself in its own pane. nohup + redirected fds let it
# survive the popup's PTY teardown (SIGHUP on close). Output goes to a log for
# troubleshooting; a failed `open` is rare here (the slug was just resolved).
open_new() {
  local slug="$1" log
  log="${TMPDIR:-/tmp}/herdr-new-coordinator-$slug.log"
  nohup "$hp_bin" --root "$hp_root" open "$slug" --new --tab >"$log" 2>&1 &
}

# 1. cwd directly inside the projects root: the popup inherits the launching
# pane's cwd, and this also covers running the script from a project shell.
case "$PWD/" in
  "$hp_root"/*)
    slug="${PWD#"$hp_root"/}"
    case "$slug" in
      */*) : ;;
      *)
        if valid_slug "$slug"; then
          open_new "$slug"
          exit 0
        fi
        ;;
    esac
    ;;
esac

# 2. The underlying tiled pane (popups only). Prefer the plugin's own
# hp_project token (set on both coordinator and thread panes); fall back to a
# cwd directly inside the projects root.
if [ -n "${HERDR_ACTIVE_PANE_ID:-}" ] && command -v herdr >/dev/null 2>&1; then
  pane_json="$(herdr pane get "$HERDR_ACTIVE_PANE_ID" 2>/dev/null || true)"
  if [ -n "$pane_json" ] && command -v jq >/dev/null 2>&1; then
    slug="$(printf '%s' "$pane_json" | jq -r '.result.pane.tokens.hp_project // empty' 2>/dev/null || true)"
    if valid_slug "$slug"; then
      open_new "$slug"
      exit 0
    fi
    cwd="$(printf '%s' "$pane_json" | jq -r '.result.pane.cwd // empty' 2>/dev/null || true)"
    if [ -n "$cwd" ]; then
      case "$cwd/" in
        "$hp_root"/*)
          slug="${cwd#"$hp_root"/}"
          case "$slug" in
            */*) : ;;
            *)
              if valid_slug "$slug"; then
                open_new "$slug"
                exit 0
              fi
              ;;
          esac
          ;;
      esac
    fi
  fi
fi

# 3. fzf picker, same list shape as herdr-pick-project.
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"
projects="$("$hp_bin" --root "$hp_root" list 2>/dev/null)" || die "'herdr-projects list' failed"
[ -n "$projects" ] || die "no projects under $hp_root yet (use prefix+shift+c to create one)"
selection="$(printf '%s\n' "$projects" | fzf \
  --prompt='new coordinator for > ' \
  --header='Enter: open another coordinator   Esc: cancel')" || exit 0
[ -n "$selection" ] || exit 0
slug="${selection%%$'\t'*}"
if valid_slug "$slug"; then
  open_new "$slug"
else
  die "unexpected project list output: $selection"
fi
