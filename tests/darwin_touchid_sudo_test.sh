#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
darwin_config="${repo_root}/nix-darwin/configuration.nix"

assert_contains() {
  local pattern="$1"
  local message="$2"
  if ! grep -Fq "$pattern" "$darwin_config"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "security.pam.services.sudo_local.touchIdAuth = true;" \
  "expected nix-darwin to enable Touch ID for sudo"
assert_contains "security.pam.services.sudo_local.reattach = true;" \
  "expected nix-darwin to enable sudo Touch ID reattach for tmux/screen"
