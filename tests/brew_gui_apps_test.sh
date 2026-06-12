#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
brewfile="${repo_root}/brew/Brewfile"
nix_gui_module="${repo_root}/modules/mac-gui-app.nix"

for cask in \
  1password \
  brave-browser \
  firefox \
  inkscape \
  karabiner-elements \
  keycastr \
  kitty \
  maccy \
  monitorcontrol \
  obsidian \
  raycast \
  scroll-reverser \
  skim \
  snipaste \
  visual-studio-code \
  wechat \
  zed \
  zotero; do
  if ! grep -Fq "cask \"${cask}\"" "$brewfile"; then
    echo "expected ${cask} to be managed as a Homebrew cask" >&2
    exit 1
  fi
done

for nix_pkg in \
  _1password-gui \
  brave \
  firefox \
  inkscape \
  karabiner-elements \
  keycastr \
  kitty \
  maccy \
  monitorcontrol \
  obsidian \
  raycast \
  scroll-reverser \
  skim \
  vscode \
  wechat \
  zed-editor \
  zotero; do
  if grep -Eq "(^|[^[:alnum:]_-])${nix_pkg}([^[:alnum:]_-]|$)" "$nix_gui_module"; then
    echo "expected ${nix_pkg} to be removed from Nix GUI packages" >&2
    exit 1
  fi
done
