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
assert_file_exists "config/aerospace/render-config.py"
assert_file_exists "config/aerospace/start_workspace_indicator.sh"
assert_file_exists "config/aerospace/workspace_indicator.swift"
assert_file_exists "config/skhd/skhdrc"
assert_file_exists "config/skhd/open_iterm2.sh"
assert_file_exists "config/skhd/toggle_kitty_dropdown.sh"

assert_module_mentions "$darwin_gui_module" ".config/aerospace/aerospace.toml" "../config/aerospace/aerospace.toml"
assert_module_mentions "$darwin_gui_module" "render-aerospace-config" "../config/aerospace/render-config.py"
assert_module_mentions "$darwin_gui_module" "start_workspace_indicator.sh" "../config/aerospace/start_workspace_indicator.sh"
assert_module_mentions "$darwin_gui_module" "workspace_indicator.swift" "../config/aerospace/workspace_indicator.swift"
assert_module_links "$darwin_module" ".skhdrc" "../config/skhd/skhdrc"
assert_module_links "$darwin_module" ".config/skhd/open_iterm2.sh" "../config/skhd/open_iterm2.sh"
assert_module_links "$darwin_module" ".config/skhd/toggle_kitty_dropdown.sh" "../config/skhd/toggle_kitty_dropdown.sh"

if grep -Fq '".config/zed/settings.json"' "${darwin_module}"; then
	echo "expected Zed settings to stay writable instead of being linked into the Nix store" >&2
	exit 1
fi
if ! grep -Fq "prepareZedSettings" "${darwin_module}" ||
	! grep -Fq "../config/zed/settings.json" "${darwin_module}"; then
	echo "expected modules/darwin.nix to initialize writable Zed settings from tracked config" >&2
	exit 1
fi

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
if ! grep -Fq "launchd.user.agents.aerospaceWorkspaceIndicator" "${darwin_gui_module}"; then
	echo "expected AeroSpace workspace indicator to be managed by nix-darwin launchd.user.agents" >&2
	exit 1
fi
if ! grep -Fq '"$app_path/Contents/MacOS/AeroSpace"' "${darwin_gui_module}"; then
	echo "expected AeroSpace launchd agent to execute the stable app bundle binary path" >&2
	exit 1
fi
if ! grep -Fq "pgrep -x AeroSpace" "${darwin_gui_module}" ||
	! grep -Fq 'kill "$pid"' "${darwin_gui_module}"; then
	echo "expected AeroSpace launch wrapper to clean up duplicate instances before launch" >&2
	exit 1
fi
if ! grep -Fq '/Applications/AeroSpace.app' "${darwin_gui_module}"; then
	echo "expected AeroSpace launchd agent to use the Homebrew-installed app path" >&2
	exit 1
fi
if grep -Fq '/Applications/Nix Apps/AeroSpace.app' "${darwin_gui_module}"; then
	echo "expected AeroSpace launchd agent not to use the Nix Apps bundle path" >&2
	exit 1
fi
if grep -Fq 'pkgs.aerospace' "${darwin_gui_module}" || grep -Fq '    aerospace' "${darwin_gui_module}"; then
	echo "expected AeroSpace app to be installed by Homebrew, not Nix packages" >&2
	exit 1
fi
if ! grep -Fq "KeepAlive = { SuccessfulExit = false; };" "${darwin_gui_module}"; then
	echo "expected AeroSpace launchd agent to restart only after unsuccessful exits" >&2
	exit 1
fi
if ! grep -Fq "monitors unavailable; keeping existing config" "${darwin_gui_module}"; then
	echo "expected AeroSpace reconfigure to preserve config until monitor state is readable" >&2
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
if ! grep -Fq 'rm -f "${homeDir}/.aerospace.toml"' "${darwin_gui_module}"; then
	echo "expected legacy ~/.aerospace.toml to be removed to avoid AeroSpace ambiguous config errors" >&2
	exit 1
fi
if grep -F 'ln -sfn' "${darwin_gui_module}" | grep -Fq '.aerospace.toml'; then
	echo "expected nix-darwin GUI module not to create legacy ~/.aerospace.toml" >&2
	exit 1
fi
if grep -F 'ln -sfn' "${darwin_gui_module}" | grep -Fq '.config/aerospace/aerospace.toml'; then
	echo "expected AeroSpace config to be generated, not symlinked directly" >&2
	exit 1
fi
if ! grep -Fq "start-at-login = false" "${repo_root}/config/aerospace/aerospace.toml"; then
	echo "expected AeroSpace self-managed login startup to be disabled" >&2
	exit 1
fi
if ! grep -Fq "exec-on-workspace-change = ['/bin/sh', '-c', 'printf . > /tmp/aerospace-workspace-indicator-dirty']" "${repo_root}/config/aerospace/aerospace.toml"; then
	echo "expected AeroSpace workspace changes to do only a lightweight dirty-file write" >&2
	exit 1
fi
assert_module_contains "services.skhd" \
	"expected modules/darwin.nix to enable skhd"
assert_module_contains "config = builtins.readFile ../config/skhd/skhdrc;" \
	"expected skhd settings to be loaded from the tracked skhdrc"

if ! grep -Fq "toggle_kitty_dropdown.sh" "${repo_root}/config/skhd/skhdrc"; then
	echo "expected skhd shortcut to use the kitty dropdown wrapper" >&2
	exit 1
fi

if grep -Riq "emacs" \
	"${repo_root}/config/aerospace" \
	"${repo_root}/config/skhd" \
	"${repo_root}/config/karabiner" \
	"${repo_root}/modules"; then
	echo "did not expect Emacs references in managed macOS configs" >&2
	exit 1
fi
