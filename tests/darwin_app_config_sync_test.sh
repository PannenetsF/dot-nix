#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
darwin_module="${repo_root}/modules/darwin.nix"
darwin_gui_module="${repo_root}/nix-darwin/gui-apps.nix"

assert_file_exists() {
	local path="$1"
	if [[ ! -f "${repo_root}/${path}" ]]; then
		echo "expected ${path} to be tracked as a source config" >&2
		exit 1
	fi
}

assert_module_links() {
	local module="$1"
	local target="$2"
	local source="$3"

	if ! grep -Fq "\"${target}\"" "${module}"; then
		echo "expected ${module#${repo_root}/} to link ${target}" >&2
		exit 1
	fi

	if ! grep -Fq "${source}" "${module}"; then
		echo "expected ${module#${repo_root}/} to source ${source}" >&2
		exit 1
	fi
}

assert_module_mentions() {
	local module="$1"
	local target="$2"
	local source="$3"

	if ! grep -Fq "${target}" "${module}"; then
		echo "expected ${module#${repo_root}/} to mention ${target}" >&2
		exit 1
	fi

	if ! grep -Fq "${source}" "${module}"; then
		echo "expected ${module#${repo_root}/} to source ${source}" >&2
		exit 1
	fi
}

assert_file_exists "config/aerospace/aerospace.toml"
assert_file_exists "config/skhd/skhdrc"
assert_file_exists "config/skhd/open_iterm2.sh"

assert_module_mentions "$darwin_gui_module" ".aerospace.toml" "../config/aerospace/aerospace.toml"
assert_module_mentions "$darwin_gui_module" ".config/aerospace/aerospace.toml" "../config/aerospace/aerospace.toml"
assert_module_links "$darwin_module" ".skhdrc" "../config/skhd/skhdrc"
assert_module_links "$darwin_module" ".config/skhd/open_iterm2.sh" "../config/skhd/open_iterm2.sh"

assert_module_contains() {
	local pattern="$1"
	local message="$2"

	if ! grep -Fq "${pattern}" "${darwin_module}"; then
		echo "${message}" >&2
		exit 1
	fi
}

if grep -Fq "launchd.agents.aerospace" "${darwin_module}"; then
	echo "expected AeroSpace LaunchAgent to move out of Home Manager darwin module" >&2
	exit 1
fi

if ! grep -Fq "launchd.user.agents.aerospace" "${darwin_gui_module}"; then
	echo "expected AeroSpace to be managed by nix-darwin launchd.user.agents" >&2
	exit 1
fi
if ! grep -Fq 'AeroSpace.app/Contents/MacOS/AeroSpace' "${darwin_gui_module}"; then
	echo "expected AeroSpace launchd agent to use the Nix package app binary" >&2
	exit 1
fi
if grep -Fq "system.activationScripts.aerospaceConfig" "${darwin_gui_module}"; then
	echo "expected AeroSpace config sync to use a nix-darwin activation hook that runs" >&2
	exit 1
fi
if ! grep -Fq "system.activationScripts.postActivation.text" "${darwin_gui_module}"; then
	echo "expected AeroSpace config sync to run during nix-darwin postActivation" >&2
	exit 1
fi

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
