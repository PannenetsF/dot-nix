#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host_module="${repo_root}/modules/host.nix"

if grep -Fq "texliveFull" "$host_module"; then
  echo "texliveFull should not be part of the default host package set" >&2
  exit 1
fi

for expected in \
  "pythonEnv = pkgs.python3.withPackages" \
  "jedi-language-server" \
  "pip" \
  "pynvim" \
  "ruff" \
  "ty"; do
  if ! grep -Fq "$expected" "$host_module"; then
    echo "expected host package set to include ${expected}" >&2
    exit 1
  fi
done
