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
assert_contains "5 = [1, 'main']" "expected workspace 5 on the first non-main external display with a main fallback"
assert_contains "7 = [1, 'main']" "expected workspace 7 on the first non-main external display with a main fallback"
assert_contains "8 = ['built-in', 'main']" "expected workspace 8 on the built-in display with a main fallback"
assert_contains "10 = ['built-in', 'main']" "expected workspace 10 on the built-in display with a main fallback"
assert_contains "start-at-login = false" "expected normal AeroSpace settings to remain"

four_display_rendered="${tmp_dir}/four-display.toml"
AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "main": false, "built_in": false},
  {"seq": 2, "main": true, "built_in": false},
  {"seq": 3, "main": false, "built_in": true},
  {"seq": 4, "main": false, "built_in": false}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${four_display_rendered}"

rendered="${four_display_rendered}"
assert_contains "1 = 'main'" "expected workspace 1 on the main display with four displays"
assert_contains "3 = 'main'" "expected workspace 3 on the main display with four displays"
assert_contains "4 = [1, 'main']" "expected workspace 4 on the first non-main external display with a main fallback"
assert_contains "6 = [1, 'main']" "expected workspace 6 on the first non-main external display with a main fallback"
assert_contains "7 = [4, 'main']" "expected workspace 7 on the second non-main external display with a main fallback"
assert_contains "8 = [4, 'main']" "expected workspace 8 on the second non-main external display with a main fallback"
assert_contains "9 = ['built-in', 'main']" "expected workspace 9 on the built-in display with a main fallback"
assert_contains "10 = ['built-in', 'main']" "expected workspace 10 on the built-in display with a main fallback"

# A stable two-display topology must replace stale numeric IDs from the old
# four-display layout. Otherwise an old monitor ID can now name the built-in
# display and steal workspaces 1-3 from main.
AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "name": "G27M7Pro", "main": true, "built_in": false},
  {"seq": 2, "name": "Built-in Retina Display", "main": false, "built_in": true}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${four_display_rendered}"

rendered="${four_display_rendered}"
assert_contains "1 = 'main'" "expected workspace 1 to follow the current main display"
assert_contains "3 = 'main'" "expected workspace 3 to follow the current main display"
assert_contains "6 = ['built-in', 'main']" "expected workspace 6 on built-in in the stable two-display topology"
assert_contains "10 = ['built-in', 'main']" "expected workspace 10 on built-in in the stable two-display topology"
if grep -Fq "1 = [2, 'main']" "${four_display_rendered}"; then
	echo "expected stale monitor ID 2 to be replaced for workspace 1" >&2
	exit 1
fi

PYTHONDONTWRITEBYTECODE=1 python3 - "${repo_root}" "${four_display_rendered}" <<'PY'
import importlib.util
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
output_path = sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "aerospace_render_config", repo_root / "config/aerospace/render-config.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
displays = [{"seq": index} for index in range(1, 5)]
assert module.should_preserve_existing_block("coregraphics", displays, output_path)
assert not module.should_preserve_existing_block("env", displays, output_path)
PY

hp_preferred_rendered="${tmp_dir}/hp-preferred.toml"
AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "name": "Built-in Retina Display", "main": true, "built_in": true},
  {"seq": 2, "name": "DELL U2720Q", "main": false, "built_in": false},
  {"seq": 3, "name": "HP Z27k G3", "main": false, "built_in": false}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${hp_preferred_rendered}"

rendered="${hp_preferred_rendered}"
assert_contains "1 = [3, 'main']" "expected workspace 1 on the HP display even when built-in is main"
assert_contains "4 = [3, 'main']" "expected workspace 4 on the HP display even when built-in is main"
assert_contains "5 = [2, 'main']" "expected workspace 5 on the DELL display when HP is preferred"
assert_contains "7 = [2, 'main']" "expected workspace 7 on the DELL display when HP is preferred"
assert_contains "8 = ['built-in', 'main']" "expected workspace 8 on the built-in display when HP is preferred"
assert_contains "10 = ['built-in', 'main']" "expected workspace 10 on the built-in display when HP is preferred"

solo_rendered="${tmp_dir}/solo.toml"
AEROSPACE_MONITORS_JSON='[
  {"seq": 1, "main": true, "built_in": true}
]' python3 \
  "${repo_root}/config/aerospace/render-config.py" \
  "${repo_root}/config/aerospace/aerospace.toml" \
  "${solo_rendered}"

if ! grep -Fq "10 = 'main'" "${solo_rendered}"; then
	echo "expected all workspaces to fall back to main display with only one display" >&2
	cat "${solo_rendered}" >&2
	exit 1
fi
