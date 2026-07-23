#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
opener="${repo_root}/config/neovide/agent-open-neovide.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

stub_neovide="${tmp_dir}/neovide"
args_log="${tmp_dir}/args.log"

cat >"$stub_neovide" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$NEOVIDE_ARGS_LOG"
STUB
chmod +x "$stub_neovide"

assert_arg() {
  local expected="$1"
  if ! grep -Fxq -- "$expected" "$args_log"; then
    echo "expected Neovide argument: $expected" >&2
    echo "actual arguments:" >&2
    sed 's/^/  /' "$args_log" >&2
    exit 1
  fi
}

json_payload='{"path":"/tmp/agent file.py","location":{"line":17,"column":9}}'
printf '%s' "$json_payload" |
  NEOVIDE_BIN="$stub_neovide" NEOVIDE_ARGS_LOG="$args_log" bash "$opener"

assert_arg "--fork"
assert_arg "--reuse-instance"
assert_arg "/tmp/agent file.py"
assert_arg "--"
assert_arg "+call cursor(17,9)"

if grep -Fxq -- "--new-window" "$args_log"; then
  echo "did not expect the agent opener to create a new Neovide window" >&2
  exit 1
fi

NEOVIDE_BIN="$stub_neovide" NEOVIDE_ARGS_LOG="$args_log" \
  bash "$opener" "/tmp/manual.py" 23 4

assert_arg "--reuse-instance"
assert_arg "/tmp/manual.py"
assert_arg "+call cursor(23,4)"
