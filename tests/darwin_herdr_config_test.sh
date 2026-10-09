#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
	echo "$1" >&2
	exit 1
}

assert_file_exists() {
	[[ -f "${repo_root}/$1" ]] || fail "expected $1 to be tracked"
}

assert_contains() {
	grep -Fq "$2" "${repo_root}/$1" \
		|| fail "expected $1 to contain: $2"
}

assert_not_contains() {
	if grep -Fq "$2" "${repo_root}/$1"; then
		fail "did not expect $1 to contain: $2"
	fi
}

assert_file_exists "config/herdr/config.toml"
assert_file_exists "nix-darwin/herdr.nix"

assert_contains "nix-darwin/configuration.nix" "./herdr.nix"
assert_contains "nix-darwin/herdr.nix" "postActivation.text"
assert_contains "nix-darwin/herdr.nix" ".config/herdr/config.toml"
assert_contains "nix-darwin/herdr.nix" "../config/herdr/config.toml"
assert_contains "nix-darwin/herdr.nix" "server reload-config"

# herdr rewrites the file via its settings UI: install a writable file, not a
# Home Manager symlink into the read-only Nix store.
assert_contains "nix-darwin/herdr.nix" 'rm -f "${homeDir}/.config/herdr/config.toml"'

# Home Manager must no longer force-link the file (the nix-darwin module owns it).
assert_not_contains "modules/darwin.nix" ".config/herdr/config.toml"

# herdr UI follows kitty's own palette (kitty auto-switches with the
# macOS light/dark appearance), not a herdr-built-in theme.
assert_contains "config/herdr/config.toml" 'name = "terminal"'

# herdr-radar follows macOS appearance and rewrites [theme] name from the
# light/dark keys; both pinned to "terminal" so the terminal-following theme
# survives its sync.
assert_contains "config/herdr/config.toml" 'light_name = "terminal"'
assert_contains "config/herdr/config.toml" 'dark_name = "terminal"'

# herdr-radar plugin: pinned install + post-template configure repair in the
# nix-darwin postActivation, and its keybindings in the template.
assert_contains "nix-darwin/herdr.nix" "hhdebb/herdr-radar"
assert_contains "nix-darwin/herdr.nix" "hhdebb.herdr-radar"
assert_contains "config/herdr/config.toml" 'command = "hhdebb.herdr-radar.view-flip"'
assert_contains "config/herdr/config.toml" 'command = "hhdebb.herdr-radar.settings"'
# prefix+a belongs to herdr-projects (upstream suggests it for radar's flip);
# radar's flip therefore rides prefix+ctrl+r with the other plugin actions.
assert_contains "config/herdr/config.toml" 'key = "prefix+ctrl+r"'
assert_contains "config/herdr/config.toml" 'key = "prefix+comma"'

# Radar is a Node plugin; the interpreter is part of the host package set.
assert_contains "modules/host.nix" "nodejs_22"

# sudo's env_reset secure_path lacks the HM profile dirs, so the herdr
# invocations must re-prepend them via env(1) or Node plugin build hooks fail
# to spawn `node` ("failed to start: No such file or directory").
assert_contains "nix-darwin/herdr.nix" 'env PATH='
assert_contains "nix-darwin/herdr.nix" "/etc/profiles/per-user/"

# Radar's first-run setup writes this exact marker block into kitty.conf; it
# must be shipped by the repo or its build hook hard-fails on the read-only
# Home Manager symlink. Ranges are derived from the plugin's font (v1.4.2).
assert_contains "config/kitty/kitty.conf" "# >>> herdr-radar font block"
assert_contains "config/kitty/kitty.conf" "symbol_map U+E1A0-U+E1BA Herdr Agent Icons Max"
assert_contains "config/kitty/kitty.conf" "symbol_map U+E1C0-U+E1C5 Herdr Agent Icons Max"
assert_contains "config/kitty/kitty.conf" "# <<< herdr-radar font block"

# herdr-projects repo picker (prefix+shift+c)
assert_file_exists "config/herdr/new-project.sh"
assert_contains "modules/darwin.nix" '".local/bin/herdr-new-project"'
assert_contains "config/herdr/config.toml" 'herdr-new-project'
assert_file_exists "config/herdr/pick-project.sh"
assert_contains "modules/darwin.nix" '".local/bin/herdr-pick-project"'
assert_contains "config/herdr/config.toml" 'herdr-pick-project'
# Attach-repos picker (prefix+shift+a)
assert_file_exists "config/herdr/add-repo.sh"
assert_contains "modules/darwin.nix" '".local/bin/herdr-add-repo"'
assert_contains "config/herdr/config.toml" 'herdr-add-repo'
# Opening from a popup pane must start the coordinator in a project tab,
# otherwise the transient popup pane takes it down with it on exit.
assert_contains "config/herdr/new-project.sh" 'open "$slug" --tab'
assert_contains "config/herdr/pick-project.sh" 'open "$slug" --tab'

echo "darwin herdr config test OK"
