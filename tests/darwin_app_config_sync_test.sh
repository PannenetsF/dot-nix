#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
darwin_module="${repo_root}/modules/darwin.nix"

assert_file_exists() {
	local path="$1"
	if [[ ! -f "${repo_root}/${path}" ]]; then
		echo "expected ${path} to be tracked as a source config" >&2
		exit 1
	fi
}

assert_module_links() {
	local target="$1"
	local source="$2"

	if ! grep -Fq "\"${target}\"" "${darwin_module}"; then
		echo "expected modules/darwin.nix to link ${target}" >&2
		exit 1
	fi

	if ! grep -Fq "${source}" "${darwin_module}"; then
		echo "expected modules/darwin.nix to source ${source}" >&2
		exit 1
	fi
}

assert_file_exists "config/aerospace/aerospace.toml"
assert_file_exists "config/skhd/skhdrc"
assert_file_exists "config/skhd/open_iterm2.sh"

assert_module_links ".aerospace.toml" "../config/aerospace/aerospace.toml"
assert_module_links ".config/aerospace/aerospace.toml" "../config/aerospace/aerospace.toml"
assert_module_links ".skhdrc" "../config/skhd/skhdrc"
assert_module_links ".config/skhd/open_iterm2.sh" "../config/skhd/open_iterm2.sh"

assert_module_contains() {
	local pattern="$1"
	local message="$2"

	if ! grep -Fq "${pattern}" "${darwin_module}"; then
		echo "${message}" >&2
		exit 1
	fi
}

assert_module_contains "launchd.agents.aerospace" \
	"expected AeroSpace to be managed by a launchd agent"
assert_module_contains 'Program =' \
	"expected AeroSpace launchd agent to define a program"
assert_module_contains 'AeroSpace.app/Contents/MacOS/AeroSpace' \
	"expected AeroSpace launchd agent to use the Nix package app binary"

if ! grep -Fq "start-at-login = false" "${repo_root}/config/aerospace/aerospace.toml"; then
	echo "expected AeroSpace self-managed login startup to be disabled" >&2
	exit 1
fi
assert_module_contains "services.skhd" \
	"expected modules/darwin.nix to enable skhd"
assert_module_contains "config = builtins.readFile ../config/skhd/skhdrc;" \
	"expected skhd settings to be loaded from the tracked skhdrc"

if grep -Riq "emacs" "${repo_root}/config" "${repo_root}/modules"; then
	echo "did not expect Emacs references in managed macOS configs" >&2
	exit 1
fi
