#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
darwin_brew_module="${repo_root}/nix-darwin/homebrew.nix"
nix_gui_module="${repo_root}/modules/mac-gui-app.nix"

for cask in \
  1password \
  firefox \
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
  if ! grep -Fq "\"${cask}\"" "$darwin_brew_module"; then
    echo "expected ${cask} to be managed by nix-darwin homebrew casks" >&2
    exit 1
  fi
done

for brew in daipeihust/tap/im-select gromgit/fuse/sshfs-mac; do
  if ! grep -Fq "\"${brew}\"" "$darwin_brew_module"; then
    echo "expected ${brew} to be managed by nix-darwin homebrew brews" >&2
    exit 1
  fi
done

for unwanted in brave-browser brave inkscape soduto demumble updf whatpulse whatpulse_chmodbpf; do
  if grep -Fq "$unwanted" "$darwin_brew_module"; then
    echo "expected ${unwanted} not to be managed by nix-darwin homebrew" >&2
    exit 1
  fi
done

for nix_pkg in \
  _1password-gui \
  firefox \
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
