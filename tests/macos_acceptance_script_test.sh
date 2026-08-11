#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/tests/macos_acceptance.sh"

assert_contains() {
  local pattern="$1"
  local message="$2"

  if ! grep -Fq "$pattern" "$script"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "Karabiner-Elements" "expected Karabiner-Elements app check"
assert_contains "Raycast" "expected Raycast app check"
assert_contains "Maccy" "expected Maccy app check"
assert_contains "Snipaste" "expected Snipaste app check"
assert_contains "check_command alacritty" "expected Alacritty command check"
assert_contains "check_command aerospace" "expected AeroSpace command check"
assert_contains '"AeroSpace"' "expected AeroSpace app check"
assert_contains "brew list --cask --versions aerospace-patched" "expected patched AeroSpace cask version check"
assert_contains "3121c4ba5862a49d834a2df301739ac95c08cc4a" "expected patched AeroSpace release commit check"
assert_contains "check_binary_contains \"/Applications/AeroSpace.app/Contents/MacOS/AeroSpace\"" "expected AeroSpace app provenance check"
assert_contains 'aerospace_cli="$(command -v aerospace || true)"' "expected the AeroSpace CLI path to be architecture independent"
assert_contains 'check_binary_contains "$aerospace_cli"' "expected AeroSpace CLI provenance check"
if grep -Fq '/opt/homebrew/bin/aerospace' "$script"; then
  echo "expected AeroSpace acceptance to support both Apple Silicon and Intel Homebrew prefixes" >&2
  exit 1
fi
assert_contains ".config/aerospace/aerospace.toml" "expected AeroSpace config check"
assert_contains "check_absent \"\${HOME}/.aerospace.toml\"" "expected legacy AeroSpace config path absence check"
assert_contains ".config/skhd/skhdrc" "expected skhd config check"
assert_contains ".config/alacritty/alacritty.toml" "expected Alacritty config check"
assert_contains "/Applications/Nix Apps/Alacritty.app" "expected Nix-installed Alacritty app check"
assert_contains ".config/kitty/kitty.conf" "expected kitty config check"
assert_contains ".config/kitty/theme.conf" "expected kitty theme check"
assert_contains "org.nix-community.home.aerospace" "expected AeroSpace LaunchAgent check"
assert_contains "org.nix-community.home.skhd" "expected skhd LaunchAgent check"
assert_contains "ApplePressAndHoldEnabled" "expected keyboard default check"
assert_contains "com.apple.dock" "expected Dock default check"
assert_contains "com.raycast.macos" "expected Raycast defaults check"
assert_contains "org.p0deje.Maccy" "expected Maccy defaults check"
assert_contains "/usr/libexec/PlistBuddy" "expected Maccy plist check to avoid hanging defaults reads"
if grep -Fq "check_default org.p0deje.Maccy" "$script"; then
  echo "expected Maccy acceptance check to avoid defaults(1), which can hang on this host" >&2
  exit 1
fi
assert_contains "emacs" "expected Emacs absence check"
