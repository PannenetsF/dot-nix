#!/usr/bin/env bash
set -euo pipefail

neovide_bin="${NEOVIDE_BIN:-/Applications/Neovide.app/Contents/MacOS/neovide}"
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
exec "$neovide_bin" \
  --fork \
  --reuse-instance \
  "$path" \
  -- \
  "+call cursor(${line},${column})"
