#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
homebrew_module="${repo_root}/nix-darwin/homebrew.nix"
darwin_config="${repo_root}/nix-darwin/configuration.nix"
gui_module="${repo_root}/modules/mac-gui-app.nix"

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
assert_contains "$homebrew_module" "enable = true;" "expected nix-darwin homebrew module to be enabled"

for cask in \
  1password \
  firefox \
  karabiner-elements \
  kitty \
  maccy \
  raycast \
  snipaste \
  visual-studio-code; do
  assert_contains "$homebrew_module" "\"$cask\"" "expected $cask to be installed as a Homebrew cask"
done

for unwanted in brave inkscape soduto updf whatpulse demumble emacs; do
  assert_not_contains "$homebrew_module" "$unwanted" "did not expect $unwanted in nix-darwin Homebrew config"
  assert_not_contains "$gui_module" "$unwanted" "did not expect $unwanted in Nix GUI packages"
done

for moved in _1password-gui karabiner-elements kitty maccy raycast vscode; do
  assert_not_contains "$gui_module" "$moved" "expected $moved to move out of Nix GUI packages"
done
