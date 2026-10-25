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

# No `doom env` generation: in Doom v2 `doom-load-envvars-file' is a
# compat stub that reads only the file's first form - the marker
# `(put 'process-environment 'doom t)' - and appends that list itself
# to `process-environment'. Emacs' call-process stops scanning the
# environment at the first non-string entry, so every subprocess
# silently inherits launchd's bare PATH (broke jka-compr's zstd/gzip
# shell path: "zstd: command not found" despite a correct session PATH).
# GUI PATH is covered by emacs-plus' EMACS_PLUS_PATH (baked into
# Emacs.app's Info.plist at pour time, applied from site-start.el),
# and -nw sessions inherit the shell's PATH. Remove any stale file
# left from the old `doom env` step so config.el can never load it.
rm -f "$DOOM_DIR/doomenv"

if [ -f "$DOOM_LOCK" ]; then
  echo "[install-doom.sh] lock file present, skipping first-time bootstrap: $DOOM_LOCK"
  exit 0
fi

echo "[install-doom.sh] first-time Doom Emacs bootstrap..."
"$EMACS_DIR/bin/doom" install --doomdir "$DOOM_DIR" --no-env
# `doom sync' alone only byte-compiles packages; without --aot every
# package keeps running as .elc until JIT lazy native-compilation catches
# up on first use, which shows up as repeated stutters and background
# gcc churn long after startup. --aot natively compiles every package
# once at bootstrap (a slow one-off, several minutes) and is a no-op
# ("if available") on Emacs builds without NATIVE_COMP.
"$EMACS_DIR/bin/doom" sync --aot

touch "$DOOM_LOCK"
echo "[install-doom.sh] Doom Emacs bootstrap done"