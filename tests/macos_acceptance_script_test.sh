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

assert_not_contains() {
  local pattern="$1"
  local message="$2"

  if grep -Fq "$pattern" "$script"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "Karabiner-Elements" "expected Karabiner-Elements app check"
assert_contains "Raycast" "expected Raycast app check"
assert_contains "Maccy" "expected Maccy app check"
assert_contains "Snipaste" "expected Snipaste app check"
assert_contains "check_command_absent alacritty" "expected Alacritty command absence check"
assert_contains "check_command_absent wezterm" "expected WezTerm command absence check"
# The retired AeroSpace stack is archived, not acceptance-checked.
assert_not_contains "check_command aerospace" "did not expect a managed AeroSpace command check"
assert_not_contains "aerospace-patched" "did not expect the retired patched cask version check"
assert_not_contains "check_launch_agent org.nix-community.home.aerospace" "did not expect a retired AeroSpace LaunchAgent check"
assert_contains ".config/skhd/skhdrc" "expected skhd config check"
assert_contains "check_absent \"\${HOME}/.config/alacritty/alacritty.toml\"" "expected managed Alacritty config to be removed"
assert_contains "check_absent \"\${HOME}/.config/wezterm/wezterm.lua\"" "expected managed WezTerm config to be removed"
assert_contains "check_absent \"/Applications/Nix Apps/Alacritty.app\"" "expected Nix-installed Alacritty app to be removed"
assert_contains "check_absent \"/Applications/WezTerm.app\"" "expected WezTerm app to be removed"
assert_contains "for removed_cask in wezterm wezterm@nightly" "expected both WezTerm casks to be absent"
assert_contains ".config/kitty/kitty.conf" "expected kitty config check"
assert_contains ".config/kitty/theme.conf" "expected kitty theme check"
assert_contains "org.nix-community.home.skhd" "expected skhd LaunchAgent check"

# herdr-remote relay + web-ui: launchd agent, loopback HTTP services, pinned
# plugins and the Herdi cask must all be acceptance-checked.
assert_contains '"Herdi"' "expected Herdi app check"
assert_contains "org.nix-community.home.herdr-remote" "expected herdr-remote relay LaunchAgent check"
assert_contains 'http://127.0.0.1:8375/' "expected herdr-remote relay HTTP check"
assert_contains 'http://127.0.0.1:7317/' "expected herdr-web-ui HTTP check"
assert_contains "devswha.herdr-web-ui" "expected herdr-web-ui plugin check"
assert_contains "herdr.push" "expected herdr-push plugin check"
assert_contains "herdr-portal" "expected herdr-portal plugin check"
assert_contains "herdr integration status" "expected agent integration status checks"
assert_contains "herdr codex integration current" "expected codex integration acceptance check"
assert_contains "herdr claude integration current" "expected claude integration acceptance check"
assert_contains 'brew list --cask --versions herdi' "expected Herdi cask version check"
assert_contains '/etc/dot-nix/window-manager' "expected acceptance to detect the activated WM, not the current Git branch"
assert_contains 'check_app OmniWM' "expected OmniWM app check"
assert_contains 'check_command omniwmctl' "expected the bundled OmniWM CLI check"
assert_contains 'check_default com.apple.spaces spans-displays 0' "expected separate Spaces for OmniWM"
assert_contains 'conflicting process still running' "expected acceptance to reject simultaneous WMs"
assert_contains 'complete manual onboarding before acceptance' "expected acceptance not to claim an unstarted OmniWM trial works"
assert_contains 'OmniWM curated keybindings seeded' "expected acceptance to verify the curated keymap"
assert_contains 'apply-hotkey-overrides.sh' "expected acceptance hint to name the keymap seeding script"
assert_contains "ApplePressAndHoldEnabled" "expected keyboard default check"
assert_contains "com.apple.dock" "expected Dock default check"
assert_contains "com.raycast.macos" "expected Raycast defaults check"
assert_contains "org.p0deje.Maccy" "expected Maccy defaults check"
assert_contains "/usr/libexec/PlistBuddy" "expected Maccy plist check to avoid hanging defaults reads"
if grep -Fq "check_default org.p0deje.Maccy" "$script"; then
  echo "expected Maccy acceptance check to avoid defaults(1), which can hang on this host" >&2
  exit 1
fi
assert_not_contains "emacs.*plus\|Emacs.*plus" "expected no emacs-plus brew formula reference in acceptance script"
