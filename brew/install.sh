#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed or not on PATH." >&2
  exit 1
fi

brew bundle --no-upgrade --file="${BREWFILE}"
