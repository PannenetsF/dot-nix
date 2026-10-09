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

# herdr-projects repo picker (prefix+shift+c)
assert_file_exists "config/herdr/new-project.sh"
assert_contains "modules/darwin.nix" '".local/bin/herdr-new-project"'
assert_contains "config/herdr/config.toml" 'herdr-new-project'
assert_contains "config/herdr/config.toml" 'herdr-projects.open'

echo "darwin herdr config test OK"
