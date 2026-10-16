#!/usr/bin/env bash
# Shared preamble for the four herdr popup launchers (new-project, pick-project,
# add-repo, new-coordinator). Each script sources the sibling copy of this file
# next to it (see the inline resolution block in each launcher); it must not be
# relied on to live anywhere on PATH. It deliberately does NOT enable
# `set -euo pipefail` itself: the sourcing script owns its own options, and this
# file must behave identically whether or not the caller set them.
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
