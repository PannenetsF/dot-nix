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
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "_HIHideMenuBar = true;" \
  "expected menu bar autohide to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "KeyRepeat = 2;" \
  "expected fast keyboard repeat to be configured"
assert_contains "$repo_root/nix-darwin/macos-defaults.nix" "ApplePressAndHoldEnabled = false;" \
  "expected press-and-hold to be disabled for key repeat"

assert_contains "$repo_root/nix-darwin/app-defaults.nix" "\"com.raycast.macos\"" \
  "expected Raycast preferences to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "\"org.p0deje.Maccy\"" \
  "expected Maccy preferences to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "\"com.Snipaste\"" \
  "expected Snipaste preferences to be configured"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "pkgs.duti" \
  "expected duti to be installed for default app handlers"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "org.mozilla.firefox https all" \
  "expected Firefox to be set as default HTTPS handler"
assert_contains "$repo_root/nix-darwin/app-defaults.nix" "com.microsoft.VSCode public.source-code all" \
  "expected VS Code to be set as default source-code handler"
