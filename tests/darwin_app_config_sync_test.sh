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

assert_file_exists "config/skhd/skhdrc"
assert_file_exists "config/skhd/toggle_kitty_dropdown.sh"
assert_file_exists "config/neovide/agent-open-neovide.sh"

assert_module_links "$darwin_module" ".skhdrc" "../config/skhd/skhdrc"
assert_module_links "$darwin_module" ".config/skhd/toggle_kitty_dropdown.sh" "../config/skhd/toggle_kitty_dropdown.sh"
assert_module_links "$darwin_module" ".local/bin/agent-open-neovide" "../config/neovide/agent-open-neovide.sh"

# The retired AeroSpace stack lives under deprecated/; the active GUI module
# must contain none of its launchd, renderer or symlink glue.
for retired_glue in \
  "launchd.user.agents.aerospace" \
  "launchd.user.agents.borders" \
  "config/aerospace" \
  "render-aerospace-config"; do
  if grep -Fq "$retired_glue" "$darwin_gui_module"; then
    echo "expected ${darwin_gui_module#${repo_root}/} not to contain retired glue: $retired_glue" >&2
    exit 1
  fi
done

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

assert_module_contains "services.skhd" \
	"expected modules/darwin.nix to enable skhd"
assert_module_contains "config = builtins.readFile ../config/skhd/skhdrc;" \
	"expected skhd settings to be loaded from the tracked skhdrc"

if ! grep -Fq "toggle_kitty_dropdown.sh" "${repo_root}/config/skhd/skhdrc"; then
	echo "expected skhd shortcut to use the kitty dropdown wrapper" >&2
	exit 1
fi

if grep -Riq "emacs" \
	"${repo_root}/config/skhd" \
	"${repo_root}/config/karabiner"; then
	echo "did not expect Emacs references in managed macOS app configs" >&2
	exit 1
fi
