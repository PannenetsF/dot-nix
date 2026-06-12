#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

eval_attr() {
  local attr="$1"
  cd "$repo_root"
  env -i \
    PATH="$PATH" \
    XDG_CACHE_HOME="$tmp_dir/cache" \
    SUDO_USER=bytedance \
    HOME= \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --impure --raw "$attr"
}

primary_user="$(eval_attr .#darwinConfigurations.aarch64-darwin.config.system.primaryUser)"
if [[ "$primary_user" != "bytedance" ]]; then
  echo "expected Darwin primaryUser to fall back to SUDO_USER" >&2
  echo "got: $primary_user" >&2
  exit 1
fi

home_dir="$(eval_attr .#darwinConfigurations.aarch64-darwin.config.users.users.bytedance.home)"
if [[ "$home_dir" != "/Users/bytedance" ]]; then
  echo "expected Darwin user home to infer /Users/bytedance under sudo" >&2
  echo "got: $home_dir" >&2
  exit 1
fi
