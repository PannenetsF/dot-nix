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
assert_module_links ".config/skhd/skhdrc" "../config/skhd/skhdrc"
assert_module_links ".config/skhd/open_iterm2.sh" "../config/skhd/open_iterm2.sh"
