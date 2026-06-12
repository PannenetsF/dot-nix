#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

activation="$(
  cd "$repo_root"
  env USER=bytedance HOME=/Users/bytedance \
    nix --extra-experimental-features 'nix-command flakes' \
    eval --impure --raw \
    .#homeConfigurations.aarch64-darwin.config.home.activation.runMyScript.data
)"

if [[ "$activation" != *"/Users/bytedance/.nix-profile/bin"* ]]; then
  echo "Darwin activation should use the Home Manager profile bin before running install-macos.sh" >&2
  printf '%s\n' "$activation" >&2
  exit 1
fi

if [[ "$activation" != *"set +u"* || "$activation" != *"hm-session-vars.sh"* || "$activation" != *"set -u"* ]]; then
  echo "Darwin activation should source hm-session-vars.sh with nounset disabled" >&2
  printf '%s\n' "$activation" >&2
  exit 1
fi

if [[ "$activation" == *"brew"*"/install.sh"* ]]; then
  echo "Darwin Home Manager activation should leave Homebrew package management to nix-darwin" >&2
  printf '%s\n' "$activation" >&2
  exit 1
fi

if [[ "$activation" != *"install-macos.sh"* ]]; then
  echo "Darwin activation should still run install-macos.sh" >&2
  printf '%s\n' "$activation" >&2
  exit 1
fi
