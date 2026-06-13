#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix_eval() {
  nix --extra-experimental-features 'nix-command flakes' eval --impure "$@"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local context="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'expected %s to be %s, got %s\n' "$context" "$expected" "$actual" >&2
    exit 1
  fi
}

cd "$repo_root"

linux_user="$(
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.aarch64-linux.config.home.username
)"
assert_eq "$linux_user" '"alice"' "Linux home.username"

linux_home="$(
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.aarch64-linux.config.home.homeDirectory
)"
assert_eq "$linux_home" '"/home/alice"' "Linux home.homeDirectory"

darwin_primary_user="$(
  USER=root HOME=/tmp/nix-hm-root-home NIX_HM_USER=bytedance NIX_HM_HOME=/Users/bytedance \
    nix_eval .#darwinConfigurations.aarch64-darwin.config.system.primaryUser
)"
assert_eq "$darwin_primary_user" '"bytedance"' "Darwin primaryUser"

darwin_user_home="$(
  USER=root HOME=/tmp/nix-hm-root-home NIX_HM_USER=bytedance NIX_HM_HOME=/Users/bytedance \
    nix_eval .#darwinConfigurations.aarch64-darwin.config.users.users.bytedance.home
)"
assert_eq "$darwin_user_home" '"/Users/bytedance"' "Darwin user home"
