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

# This also runs for existing installations: Emacs upgrades change the ABI
# cache directory even when the first-install lock is already present.
# cl-macs loads before Doom redirects its cache, outside package AOT.
emacs --batch -Q --eval '
  (when (and (fboundp (quote native-comp-available-p))
             (native-comp-available-p))
    (require (quote comp))
    (when (and (boundp (quote comp-native-version-dir))
               (fboundp (quote comp-el-to-eln-filename)))
    (let* ((source (locate-library "cl-macs.el"))
           (name (and source (file-name-nondirectory
                              (comp-el-to-eln-filename source))))
           (current (and name
                         (catch (quote found)
                           (dolist (dir native-comp-eln-load-path)
                             (let ((file (expand-file-name
                                          name (expand-file-name comp-native-version-dir dir))))
                               (when (and (file-exists-p file)
                                          (not (file-newer-than-file-p source file)))
                                 (throw (quote found) file))))))))
        (when (and source (not current)) (native-compile source)))))'

if [ -f "$DOOM_LOCK" ]; then
  echo "[install-doom.sh] lock file present, skipping first-time bootstrap: $DOOM_LOCK"
  exit 0
fi

echo "[install-doom.sh] first-time Doom Emacs bootstrap..."
"$EMACS_DIR/bin/doom" install --doomdir "$DOOM_DIR" --no-env
# `doom sync' alone only byte-compiles packages; without --aot every
# package keeps running as .elc until JIT lazy native-compilation catches
# up on first use, which shows up as repeated stutters and background
# gcc churn long after startup. Doom v2's `--aot` is incremental
# (only packages changed by THIS sync), so pair it with `--rebuild` to
# unconditionally rebuild and AOT-compile every package. On a fresh
# bootstrap everything is new anyway, and this stays correct when
# straight's repo cache survives a failed run.
#
# Post-install full rebuild (emptied eln cache or Emacs major upgrade):
#   LSP_USE_PLISTS=1 ~/.config/emacs/bin/doom sync --aot --rebuild
# New/updated packages only: LSP_USE_PLISTS=1 doom sync --aot --no-env
# LSP_USE_PLISTS=1: the AOT compile workers must see it, or lsp-mode's
# accessors get baked in hash-table form while runtime runs plist mode
# (flycheck errors on every diagnostic). The persistent fix for
# post-bootstrap JIT workers is native-comp-async-env-modifier-form in
# dot-doom config.el.
LSP_USE_PLISTS=1 "$EMACS_DIR/bin/doom" sync --aot --rebuild

# Doom/straight compiles package build directories recursively, including
# unloaded modes and LSP clients. Loading every mode in another process does
# not preserve runtime initialization and can run unrelated mode hooks.

touch "$DOOM_LOCK"
echo "[install-doom.sh] Doom Emacs bootstrap done"
