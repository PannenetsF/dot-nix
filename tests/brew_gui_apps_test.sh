#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
homebrew_module="${repo_root}/nix-darwin/homebrew.nix"
darwin_config="${repo_root}/nix-darwin/configuration.nix"
gui_module="${repo_root}/nix-darwin/gui-apps.nix"
old_gui_module="${repo_root}/modules/mac-gui-app.nix"

assert_contains() {
  local file="$1"
  local text="$2"
  local message="$3"

  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  local message="$3"

  if grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "$darwin_config" "./homebrew.nix" "expected nix-darwin to import homebrew.nix"
assert_contains "$darwin_config" "./gui-apps.nix" "expected nix-darwin to import gui-apps.nix"
assert_contains "$homebrew_module" "enable = true;" "expected nix-darwin homebrew module to be enabled"
assert_contains "$gui_module" "pkgsUnstable.alacritty" "expected Alacritty to be installed from nixpkgs unstable"
assert_not_contains "$homebrew_module" '"alacritty"' "did not expect the deprecated Alacritty Homebrew cask"
assert_contains "$homebrew_module" '"font-ubuntu-mono-nerd-font"' "expected the terminal-safe UbuntuMono Nerd Font cask"
assert_not_contains "$homebrew_module" '"font-ubuntu-nerd-font"' "did not expect the proportional Ubuntu Nerd Font cask"
assert_contains "$homebrew_module" "\"dot-nix/local\"" "expected local tap to provide patched casks"
assert_contains "$homebrew_module" "../config/homebrew/Casks/aerospace-patched.rb" "expected the patched AeroSpace cask to come from a tracked source"
assert_contains "$homebrew_module" '"${localTapPath}/Casks/aerospace-patched.rb"' "expected activation to stage the patched AeroSpace cask in the local tap"
assert_contains "$homebrew_module" "trust dot-nix/local" "expected local tap to be trusted before Homebrew bundle"
assert_contains "$homebrew_module" "branch -M main" "expected an existing local tap branch to be renamed without losing history"
assert_contains "$homebrew_module" "symbolic-ref HEAD refs/heads/main" "expected the generated local tap to use a deterministic main branch"
assert_contains "$homebrew_module" "pull --ff-only -q origin main" "expected the installed local tap checkout to refresh before cask migration"
assert_contains "$homebrew_module" 'aerospacePatchedVersion = "0.21.3-Beta-pf.1";' "expected the patched AeroSpace release version to be pinned"
assert_contains "$homebrew_module" "fetch --cask dot-nix/local/aerospace-patched" "expected the patched cask to be verified before migration"
assert_contains "$homebrew_module" "fetch --cask nikitabobko/tap/aerospace" "expected the upstream rollback cask to be cached before migration"
assert_contains "$homebrew_module" "CRITICAL: failed to restore upstream AeroSpace" "expected failed rollback to be reported explicitly"
assert_contains "$homebrew_module" "migrating AeroSpace to dot-nix/local/aerospace-patched" "expected an explicit migration from the upstream cask"
assert_contains "$homebrew_module" "untap nikitabobko/tap" "expected the obsolete upstream AeroSpace tap to be removed"
assert_not_contains "$homebrew_module" '      "nikitabobko/tap"' "did not expect the upstream AeroSpace tap in the declarative tap list"
assert_not_contains "$homebrew_module" '      "nikitabobko/tap/aerospace"' "did not expect the upstream AeroSpace cask in the declarative cask list"
assert_contains "$homebrew_module" "untap whatpulse/whatpulse" "expected stale upstream WhatPulse tap to be removed before Homebrew bundle"
assert_contains "$homebrew_module" "whatpulse-mac-arm-latest.dmg" "expected WhatPulse cask to use the working latest DMG URL"
assert_not_contains "$homebrew_module" "\"whatpulse/whatpulse\"" "did not expect stale upstream WhatPulse tap"
assert_not_contains "$homebrew_module" "trust --tap whatpulse/whatpulse" "did not expect trust bootstrap for stale upstream WhatPulse tap"

if [[ -e "$old_gui_module" ]]; then
  echo "expected modules/mac-gui-app.nix to be removed after moving GUI app management to nix-darwin" >&2
  exit 1
fi

for cask in \
  1password \
  dot-nix/local/aerospace-patched \
  chatgpt \
  cc-switch \
  claude \
  claude-code \
  codex \
  codex-app \
  firefox \
  karabiner-elements \
  kitty \
  maccy \
  microsoft-edge \
  raycast \
  snipaste \
  visual-studio-code \
  dot-nix/local/whatpulse-chmodbpf \
  dot-nix/local/whatpulse; do
  assert_contains "$homebrew_module" "\"$cask\"" "expected $cask to be installed as a Homebrew cask"
done

for unwanted in brave inkscape soduto updf demumble emacs; do
  assert_not_contains "$homebrew_module" "$unwanted" "did not expect $unwanted in nix-darwin Homebrew config"
  assert_not_contains "$gui_module" "$unwanted" "did not expect $unwanted in Nix GUI packages"
done

for moved in _1password-gui karabiner-elements kitty maccy raycast vscode; do
  assert_not_contains "$gui_module" "$moved" "expected $moved to move out of Nix GUI packages"
done

assert_contains "$gui_module" "aerospace" "expected AeroSpace to be managed from nix-darwin GUI module"
assert_not_contains "$gui_module" "    aerospace" "expected AeroSpace app to be installed by Homebrew, not Nix packages"
assert_contains "$gui_module" 'config.homebrew.brewPrefix' "expected AeroSpace CLI paths to follow the active Homebrew architecture"
assert_not_contains "$gui_module" "/opt/homebrew/bin/aerospace" "did not expect an Apple-Silicon-only AeroSpace CLI path"
assert_contains "$gui_module" "nerd-fonts.shure-tech-mono" "expected desktop fonts to move into nix-darwin GUI module"
assert_contains "$gui_module" "sketchybar-app-font" "expected sketchybar app font to move into nix-darwin GUI module"
