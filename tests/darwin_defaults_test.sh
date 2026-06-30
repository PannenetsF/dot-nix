#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Fq "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "$repo_root/nix-darwin/configuration.nix" "./macos-defaults.nix" \
  "expected nix-darwin configuration to import macOS defaults"
assert_contains "$repo_root/nix-darwin/configuration.nix" "./app-defaults.nix" \
  "expected nix-darwin configuration to import app defaults"

assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "autohide = true;" \
  "expected Dock autohide to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "orientation = \"left\";" \
  "expected Dock to be positioned on the left"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "_HIHideMenuBar = true;" \
  "expected menu bar autohide to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "KeyRepeat = 2;" \
  "expected fast keyboard repeat to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "ApplePressAndHoldEnabled = false;" \
  "expected press-and-hold to be disabled for key repeat"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "Sound = true;" \
  "expected Sound to be shown in the menu bar"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "NowPlaying = false;" \
  "expected Now Playing/Music to be hidden from the menu bar"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "\"NSStatusItem VisibleCC Item-0\" = false;" \
  "expected Spotlight to be hidden from the menu bar"

assert_contains "$repo_root/nix-darwin/app-defaults.nix" "write_user_default com.raycast.macos" \
  "expected Raycast preferences to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "alwaysAllowCommandDeeplinking" \
  "expected Raycast command deeplinking preference to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "permissions.folders.read:\${homeDir}/Downloads" \
  "expected Raycast folder permission preference to be derived from the managed home directory"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "org.p0deje.Maccy.plist" \
  "expected Maccy preferences to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "write_user_default com.Snipaste" \
  "expected Snipaste preferences to be configured"
if grep -Fq "system.defaults.CustomUserPreferences" "$repo_root/nix-darwin/app-defaults.nix"; then
  echo "expected app defaults to avoid nix-darwin CustomUserPreferences XML defaults writes" >&2
  exit 1
fi
if grep -Fq "defaults write org.p0deje.Maccy" "$repo_root/nix-darwin/app-defaults.nix"; then
  echo "expected Maccy defaults to avoid defaults(1), which can hang on this host" >&2
  exit 1
fi
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "/usr/libexec/PlistBuddy" \
  "expected Maccy preferences to be written directly to the plist"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "maccy_plist=\"\${homeDir}/Library/Preferences/org.p0deje.Maccy.plist\"" \
  "expected Maccy plist path to be derived from the managed home directory"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "pkgs.duti" \
  "expected duti to be installed for default app handlers"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "sudo -u \${username} duti" \
  "expected default app handlers to run duti as the login user"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "org.mozilla.firefox https all" \
  "expected Firefox to be set as default HTTPS handler"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "com.microsoft.VSCode public.source-code all" \
  "expected VS Code to be set as default source-code handler"
