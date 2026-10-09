#!/usr/bin/env bash
set -euo pipefail

neovide_bin="${NEOVIDE_BIN:-/Applications/Neovide.app/Contents/MacOS/neovide}"
# Homebrew's nvim is intentionally not installed; Finder-launched GUI apps
# also don't inherit the shell PATH, so pin the nix-profile nvim explicitly.
neovim_bin="${NEOVIM_NVIM_BIN:-/etc/profiles/per-user/bytedance/bin/nvim}"
payload_file=""

cleanup() {
  if [[ -n "$payload_file" ]]; then
    rm -f "$payload_file"
  fi
}
trap cleanup EXIT

read_payload_field() {
  local key="$1"
  /usr/bin/plutil -extract "$key" raw -o - "$payload_file" 2>/dev/null || true
}

if (( $# > 0 )); then
  path="$1"
  line="${2:-1}"
  column="${3:-1}"
else
  payload_file="$(/usr/bin/mktemp -t agent-open-neovide)"
  /bin/cat >"$payload_file"
  path="$(read_payload_field path)"
  line="$(read_payload_field location.line)"
  column="$(read_payload_field location.column)"
fi

if [[ -z "${path:-}" ]]; then
  echo "agent-open-neovide: missing file path" >&2
  exit 2
fi

case "${line:-}" in
  "" | *[!0-9]*) line=1 ;;
esac
case "${column:-}" in
  "" | *[!0-9]*) column=1 ;;
esac

if [[ ! -x "$neovide_bin" ]]; then
  echo "agent-open-neovide: Neovide executable not found: $neovide_bin" >&2
  exit 1
fi

# --reuse-instance sends subsequent files to the existing Neovide process.
# Without --new-window, all agent file opens reuse the same GUI window.
neovim_bin_args=()
if [[ -x "$neovim_bin" ]]; then
  neovim_bin_args+=(--neovim-bin "$neovim_bin")
fi
exec "$neovide_bin" \
  --fork \
  --reuse-instance \
  "${neovim_bin_args[@]}" \
  "$path" \
  -- \
  "+call cursor(${line},${column})"
