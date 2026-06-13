#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix_eval() {
  nix --extra-experimental-features 'nix-command flakes' eval --impure "$@"
}

cd "$repo_root"

darwin_completion="$(nix_eval .#darwinConfigurations.aarch64-darwin.config.programs.zsh.enableCompletion)"
if [[ "$darwin_completion" != "false" ]]; then
  echo "expected nix-darwin system zsh completion to stay disabled" >&2
  exit 1
fi

darwin_bash_completion="$(nix_eval .#darwinConfigurations.aarch64-darwin.config.programs.zsh.enableBashCompletion)"
if [[ "$darwin_bash_completion" != "false" ]]; then
  echo "expected nix-darwin system zsh bash completion to stay disabled" >&2
  exit 1
fi

hm_completion="$(nix_eval .#homeConfigurations.aarch64-darwin.config.programs.zsh.enableCompletion)"
if [[ "$hm_completion" != "true" ]]; then
  echo "expected Home Manager user zsh completion to remain enabled" >&2
  exit 1
fi
