#!/usr/bin/env bash
# Doom Emacs bootstrap for macOS and Linux.
#
# This script is invoked from Nix activation (nix-darwin postActivation on
# macOS, Home Manager activation on Linux) after the Emacs binary is available
# (Homebrew on macOS, Nix profile on Linux).
#
# Sources install-common.sh for sync_config_repo, so it must be co-located
# with that file in the Nix store. Nix modules reference this script with
# the directory form:
#   bash ${../.}/install-doom.sh

set -e

INSTALL_LOG_PREFIX="[install-doom.sh]"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/install-common.sh"

DOOM_LOCK="$HOME/pf-init-doom"
DOOM_DIR="$HOME/.config/doom"
EMACS_DIR="$HOME/.config/emacs"

sync_config_repo "doom config" \
  "https://github.com/PannenetsF/dot-doom.git" "$DOOM_DIR"
sync_config_repo "doom emacs" \
  "https://github.com/doomemacs/doomemacs" "$EMACS_DIR"

if ! command -v emacs >/dev/null 2>&1; then
  echo "[install-doom.sh] emacs binary not found, skipping doom bootstrap"
  exit 0
fi

# Refresh the Doom env file every activation — Nix profile or Homebrew
# prefix changes can shift binary paths and a stale env file breaks
# vterm, lsp servers, and other subprocess-spawning packages.
echo "[install-doom.sh] refreshing doom env..."
"$EMACS_DIR/bin/doom" env -o "$DOOM_DIR/doomenv" --allow-all || true

if [ -f "$DOOM_LOCK" ]; then
  echo "[install-doom.sh] lock file present, skipping first-time bootstrap: $DOOM_LOCK"
  exit 0
fi

echo "[install-doom.sh] first-time Doom Emacs bootstrap..."
"$EMACS_DIR/bin/doom" install --doomdir "$DOOM_DIR" --no-env
"$EMACS_DIR/bin/doom" sync

touch "$DOOM_LOCK"
echo "[install-doom.sh] Doom Emacs bootstrap done"