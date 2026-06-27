#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

rendered="${tmp_dir}/aerospace.toml"

AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "main": false, "built_in": false},
  {"seq": 2, "main": true, "built_in": false},
  {"seq": 3, "main": false, "built_in": true}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${rendered}"

assert_contains() {
	local pattern="$1"
	local message="$2"

	if ! grep -Fq "${pattern}" "${rendered}"; then
		echo "${message}" >&2
		echo "rendered config:" >&2
		cat "${rendered}" >&2
		exit 1
	fi
}

assert_contains "1 = 'main'" "expected workspace 1 on the main display"
assert_contains "4 = 'main'" "expected workspace 4 on the main display"
assert_contains "5 = 1" "expected workspace 5 on the first non-main external display"
assert_contains "6 = 1" "expected workspace 6 on the first non-main external display"
assert_contains "7 = 'built-in'" "expected workspace 7 on the built-in display"
assert_contains "8 = 'built-in'" "expected workspace 8 on the built-in display"
assert_contains "start-at-login = false" "expected normal AeroSpace settings to remain"

solo_rendered="${tmp_dir}/solo.toml"
AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "main": true, "built_in": true}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${solo_rendered}"

if ! grep -Fq "8 = 'main'" "${solo_rendered}"; then
	echo "expected all workspaces to fall back to main display with only one display" >&2
	cat "${solo_rendered}" >&2
	exit 1
fi
