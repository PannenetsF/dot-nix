#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_file_exists() {
	local path="$1"
	if [[ ! -f "${repo_root}/${path}" ]]; then
		echo "expected ${path} to be tracked" >&2
		exit 1
	fi
}

assert_contains() {
	local file="$1"
	local pattern="$2"
	local message="$3"
	if ! grep -Fq "$pattern" "${repo_root}/${file}"; then
		echo "$message" >&2
		exit 1
	fi
}

assert_file_exists "config/kitty/kitty.conf"
assert_file_exists "config/kitty/tab_bar.py"
assert_file_exists "config/kitty/dark-theme.auto.conf"
assert_file_exists "config/kitty/light-theme.auto.conf"
assert_file_exists "config/kitty/no-preference-theme.auto.conf"
assert_file_exists "config/kitty/saved-session.conf"
assert_file_exists "config/kitty/theme.conf"

assert_contains ".gitmodules" "path = config/kitty/kitty-themes" \
	"expected kitty themes to be tracked as a submodule"
assert_contains ".gitmodules" "url = https://github.com/dexpota/kitty-themes.git" \
	"expected kitty themes submodule to use the upstream theme repo"

assert_contains "modules/darwin.nix" '".config/kitty/kitty.conf"' \
	"expected Home Manager to manage ~/.config/kitty/kitty.conf"
assert_contains "modules/darwin.nix" '".config/kitty/tab_bar.py"' \
	"expected Home Manager to manage ~/.config/kitty/tab_bar.py"
assert_contains "modules/darwin.nix" '".config/kitty/theme.conf"' \
	"expected Home Manager to manage ~/.config/kitty/theme.conf"
assert_contains "modules/darwin.nix" "../config/kitty/kitty.conf" \
	"expected Home Manager to source kitty config from this repo"

if grep -Fq "dot-kitty" "${repo_root}/install-macos.sh"; then
	echo "expected install-macos.sh not to fetch dot-kitty during activation" >&2
	exit 1
fi
if grep -Fq "KITTY_CONFIG_REPO" "${repo_root}/install-macos.sh"; then
	echo "expected install-macos.sh not to manage kitty config repository" >&2
	exit 1
fi
