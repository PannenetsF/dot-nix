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
assert_contains "$repo_root/nix-darwin/configuration.nix" "services.openssh.enable = true;" \
  "expected macOS OpenSSH server to be enabled"
assert_contains "$repo_root/nix-darwin/configuration.nix" "networking.wakeOnLan.enable = true;" \
  "expected Wake-on-network to be enabled"
assert_contains "$repo_root/nix-darwin/configuration.nix" "pmset -c sleep 0 displaysleep 0 disksleep 0" \
  "expected AC power to keep the machine awake for SSH access"
assert_contains "$repo_root/nix-darwin/configuration.nix" "launchd.daemons.acPowerCaffeinate" \
  "expected caffeinate to be managed as a system daemon"
assert_contains "$repo_root/nix-darwin/configuration.nix" "/usr/bin/caffeinate -s" \
  "expected caffeinate to prevent system sleep while on AC power"
assert_contains "$repo_root/nix-darwin/configuration.nix" "remoteManagementCurtainMode" \
  "expected Remote Management to be configured for curtain-mode clients"
assert_contains "$repo_root/nix-darwin/configuration.nix" "ARD_AllLocalUsers -bool false" \
  "expected Remote Management to allow only specified users"
assert_contains "$repo_root/nix-darwin/configuration.nix" "VNCLegacyConnectionsEnabled -bool false" \
  "expected legacy VNC password access to be disabled"
assert_contains "$repo_root/nix-darwin/configuration.nix" "dscl . -create /Users/\${username} naprivs -1073741569" \
  "expected the login user to receive full Apple Remote Desktop privileges"

assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "autohide = true;" \
  "expected Dock autohide to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "orientation = \"bottom\";" \
  "expected Dock to be positioned on the bottom for AeroSpace hidden-window parking"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "_HIHideMenuBar = true;" \
  "expected menu bar autohide to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "KeyRepeat = 2;" \
  "expected fast keyboard repeat to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "ApplePressAndHoldEnabled = false;" \
  "expected press-and-hold to be disabled for key repeat"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "\"com.apple.keyboard.fnState\" = true;" \
  "expected F1-F12 to behave as standard function keys"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "refreshFunctionKeyMode" \
  "expected activation to refresh function key mode for Karabiner"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "Karabiner-Core-Service-rev2" \
  "expected Karabiner to be restarted after function key defaults are applied"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "Sound = true;" \
  "expected Sound to be shown in the menu bar"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "NowPlaying = false;" \
  "expected Now Playing/Music to be hidden from the menu bar"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "\"NSStatusItem VisibleCC Item-0\" = false;" \
  "expected Spotlight to be hidden from the menu bar"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "spans-displays = true;" \
  "expected Displays have separate Spaces to be disabled for AeroSpace stability"

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
