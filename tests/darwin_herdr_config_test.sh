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
	grep -Fq -- "$2" "${repo_root}/$1" \
		|| fail "expected $1 to contain: $2"
}

assert_not_contains() {
	if grep -Fq -- "$2" "${repo_root}/$1"; then
		fail "did not expect $1 to contain: $2"
	fi
}

assert_file_exists "config/herdr/config.toml"
assert_file_exists "nix-darwin/herdr.nix"
assert_file_exists "nix-darwin/herdr-remote.nix"
assert_file_exists "modules/herdr.nix"
assert_file_exists "install-herdr-plugins.sh"

# The platform-independent activation body lives in one shared script used by
# BOTH nix-darwin (privilege-crossing wrapper below) and Home Manager on Linux.
body="install-herdr-plugins.sh"

assert_contains "nix-darwin/configuration.nix" "./herdr.nix"
assert_contains "nix-darwin/configuration.nix" "./herdr-remote.nix"
assert_contains "nix-darwin/herdr.nix" "postActivation.text"
assert_contains "nix-darwin/herdr.nix" "../install-herdr-plugins.sh"
assert_contains "nix-darwin/herdr.nix" "HERDR_TEMPLATE="
# The macOS layer runs the loopback relay, so only it hands the push plugin
# its relay URL; the Linux wrapper passes nothing and the shared body skips
# the whole push block without it.
assert_contains "nix-darwin/herdr.nix" "HERDR_PUSH_RELAY_URL="
assert_contains "nix-darwin/herdr.nix" "http://127.0.0.1:8375"
assert_not_contains "modules/herdr.nix" "HERDR_PUSH_RELAY_URL"
assert_contains "$body" '$HOME/.config/herdr'
assert_contains "nix-darwin/herdr.nix" "../config/herdr/config.toml"
assert_contains "modules/herdr.nix" "../config/herdr/config.toml"
assert_contains "$body" "server reload-config"

# Home Manager on Linux runs the same body directly, as the user (no sudo).
assert_contains "modules/herdr.nix" "home.activation.herdrPlugins"
assert_contains "modules/herdr.nix" "../install-herdr-plugins.sh"
assert_contains "home.nix" "./modules/herdr.nix"

# herdr rewrites the file via its settings UI: install a writable file, not a
# Home Manager symlink into the read-only Nix store. The live path is held in
# a `live` variable (the backup/diff block above uses it too).
assert_contains "$body" 'rm -f "$live"'

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

# herdr-radar plugin: pinned fork install + post-template configure repair in
# the nix-darwin postActivation, and its keybindings in the template.
assert_contains "$body" "PannenetsF/herdr-radar"
assert_contains "$body" "hhdebb.herdr-radar"
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
assert_contains "nix-darwin/herdr.nix" "launchctl asuser"
# Mac-only concerns must not leak into the shared body.
assert_not_contains "$body" "launchctl"
assert_not_contains "$body" "homebrew"
assert_not_contains "$body" "chown"

# Radar's first-run setup writes this exact marker block into kitty.conf; it
# must be shipped by the repo or its build hook hard-fails on the read-only
# Home Manager symlink. Ranges are derived from the plugin's font (v1.4.4-pf.6).
assert_contains "config/kitty/kitty.conf" "# >>> herdr-radar font block"
assert_contains "config/kitty/kitty.conf" "symbol_map U+E1A0-U+E1BA Herdr Agent Icons Max"
assert_contains "config/kitty/kitty.conf" "symbol_map U+E1C0-U+E1C5 Herdr Agent Icons Max"
assert_contains "config/kitty/kitty.conf" "# <<< herdr-radar font block"

# herdr-web-ui plugin: pinned install + immediate start action (its startup
# hook only runs when herdr itself starts).
assert_contains "$body" "devswha/herdr-web-ui"
assert_contains "$body" "v0.4.11"
assert_contains "$body" "action invoke start"
assert_contains "$body" "--plugin devswha.herdr-web-ui"

# herdr-portal: forked pinned tag (unknown-state agents stay visible in a
# multi-agent tab), on-demand only — activation must not open the board
# itself — with both keybindings in the template on the o namespace.
assert_contains "$body" "PannenetsF/herdr-portal"
assert_contains "$body" "v1.2.1-pf.1"
assert_contains "config/herdr/config.toml" 'key = "prefix+shift+o"'
assert_contains "config/herdr/config.toml" 'command = "herdr-portal.open-board"'
assert_contains "config/herdr/config.toml" 'key = "prefix+ctrl+o"'
assert_contains "config/herdr/config.toml" 'command = "herdr-portal.open-web"'

# Bun (>= 1.4) is the web-ui build/startup runtime and must be in the host set.
assert_contains "modules/host.nix" "bun"

# herdr-push plugin: pinned HEAD, opt-in by env, relay URL seeded once into
# the plugin's own .env and never overwritten (local tunnel edits survive).
assert_contains "$body" "dcolinmorgan/herdr-push"
assert_contains "$body" "f4fdb06d5413ac2d96ca225ea33f288f41bfc001"
assert_contains "$body" "HERDR_PUSH_RELAY_URL"
assert_contains "$body" "plugin config-dir herdr.push"
assert_contains "$body" "chmod 0600"

# herdr-remote relay: pinned fetchFromGitHub source run via uv as a launchd
# user agent, loopback by default, machine-local config.env sourced if present.
assert_contains "nix-darwin/herdr-remote.nix" "fetchFromGitHub"
assert_contains "nix-darwin/herdr-remote.nix" 'owner = "dcolinmorgan"'
assert_contains "nix-darwin/herdr-remote.nix" '"v0.8.1"'
assert_contains "nix-darwin/herdr-remote.nix" "uv run"
assert_contains "nix-darwin/herdr-remote.nix" "127.0.0.1"
assert_contains "nix-darwin/herdr-remote.nix" "launchd.user.agents.herdrRemote"
assert_contains "nix-darwin/herdr-remote.nix" "org.nix-community.home.herdr-remote"
assert_contains "nix-darwin/herdr-remote.nix" "kickstart"
assert_contains "nix-darwin/herdr-remote.nix" ".config/herdr-remote/config.env"
assert_contains "nix-darwin/herdr-remote.nix" "Library/Logs/herdr-remote"

# Herdi.app rides the local tap as a tracked cask (upstream has no brew cask).
assert_file_exists "config/homebrew/Casks/herdi.rb"
assert_contains "config/homebrew/Casks/herdi.rb" 'cask "herdi"'
assert_contains "config/homebrew/Casks/herdi.rb" "dcolinmorgan/herdr-remote"
assert_contains "nix-darwin/homebrew.nix" "../config/homebrew/Casks/herdi.rb"
assert_contains "nix-darwin/homebrew.nix" '"dot-nix/local/herdi"'

# roadboard plugin: local-checkout link in postActivation (never hard-fails),
# and prefix+shift+r opens its registered popup pane via a plugin_action.
assert_contains "$body" "plugin link \"\$roadboard_src\""
assert_contains "config/herdr/config.toml" 'key = "prefix+shift+r"'
assert_contains "config/herdr/config.toml" 'command = "roadboard.open"'
assert_contains "config/herdr/config.toml" 'type = "plugin_action"'

# herdr-projects repo picker (prefix+shift+c)
assert_file_exists "config/herdr/new-project.sh"
assert_contains "config/herdr/config.toml" 'herdr-new-project'
assert_file_exists "config/herdr/pick-project.sh"
assert_contains "config/herdr/config.toml" 'herdr-pick-project'
# All four popup launchers are linked from the single shared
# modules/herdr-launchers.nix, imported from every host layer (macOS and
# Linux). The key bindings ship unconditionally in config.toml, so the
# links must be platform-independent — a missing one makes prefix+ctrl+p
# (and the rest of the project namespace) silently no-op on that layer.
assert_file_exists "modules/herdr-launchers.nix"
assert_contains "home.nix" "./modules/herdr-launchers.nix"
for launcher in herdr-new-project herdr-pick-project herdr-add-repo herdr-new-coordinator; do
	assert_contains "modules/herdr-launchers.nix" "\".local/bin/$launcher\""
	assert_not_contains "modules/herdr.nix" "\".local/bin/$launcher\""
	assert_not_contains "modules/darwin.nix" "\".local/bin/$launcher\""
done
# Attach-repos picker (prefix+shift+a)
assert_file_exists "config/herdr/add-repo.sh"
assert_contains "config/herdr/config.toml" 'herdr-add-repo'
# Opening from a popup pane must start the coordinator in a project tab,
# otherwise the transient popup pane takes it down with it on exit. The open
# call lives in an `open_project` helper that also handles --rebind, so the
# slug variable is `open_slug` there.
assert_contains "config/herdr/new-project.sh" 'open "$open_slug" --tab'
assert_contains "config/herdr/pick-project.sh" 'open "$open_slug" --tab'
# The name prompt is free-form: the plugin binary derives the slug itself,
# so capitals/spaces ("Erdos", "my project") must not be rejected locally.
assert_contains "config/herdr/new-project.sh" '-- "$name"'
assert_not_contains "config/herdr/new-project.sh" 'invalid slug'

# --- Wrapper-script hardening (PATH self-sufficiency, @ guards, slug locks) ---
#
# All four launchers must be runnable from a bare popup environment: herdr's
# popup spawns them with a minimal PATH that lacks the HM profile and Homebrew.
# The PATH-prepend dirs now live once in the shared sibling library, and every
# launcher sources that library next to its own resolved path.
assert_file_exists "config/herdr/herdr-popup-lib.sh"
assert_contains "config/herdr/herdr-popup-lib.sh" "/etc/profiles/per-user/"
assert_contains "config/herdr/herdr-popup-lib.sh" "/opt/homebrew/bin"
for s in new-project pick-project add-repo new-coordinator; do
	assert_contains "config/herdr/$s.sh" "herdr-popup-lib.sh"
done

# Repo paths containing @ are rejected before reaching the plugin (they break
# TOML/shell handling); both scripts that accept repo paths must guard them.
assert_contains "config/herdr/new-project.sh" '*@*)'
assert_contains "config/herdr/add-repo.sh" '*@*)'

# add-repo.sh: idempotent attach (tolerate "already listed"), no tomllib
# dependency, find matches worktree .git *files* (not just .git directories),
# python strips newlines with rstrip("\n") (not .strip() which also eats
# meaningful whitespace).
assert_contains "config/herdr/add-repo.sh" "already listed"
assert_not_contains "config/herdr/add-repo.sh" "import tomllib"
assert_contains "config/herdr/add-repo.sh" "-type f"
assert_contains "config/herdr/add-repo.sh" ".git"
assert_contains "config/herdr/add-repo.sh" 'rstrip("\n")'
assert_not_contains "config/herdr/add-repo.sh" "line.strip()"

# new-project.sh: EOF on the name prompt is a cancel (exit 0); the slug sed
# capture group is locked to slug characters [a-z0-9-]; --rebind recovers
# from a dead recorded socket.
assert_contains "config/herdr/new-project.sh" "read -r name || exit 0"
assert_contains "config/herdr/new-project.sh" '[a-z0-9-]'
assert_contains "config/herdr/new-project.sh" "--rebind"
assert_contains "config/herdr/new-project.sh" 's/^created `\([a-z0-9-]*\)` at'

# pick-project.sh: slug regex guard on list output; --rebind.
assert_contains "config/herdr/pick-project.sh" '^[a-z0-9][a-z0-9-]'
assert_contains "config/herdr/pick-project.sh" "--rebind"

# nix-darwin: config.toml backup + diff before overwrite.
assert_contains "$body" "config.toml.bak-"
assert_contains "$body" "diff -u"

[[ -x "${repo_root}/install-herdr-plugins.sh" ]] || fail "install-herdr-plugins.sh must be executable"

echo "herdr config activation test OK"
