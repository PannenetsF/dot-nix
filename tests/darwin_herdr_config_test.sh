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
# Home Manager symlink. Ranges are derived from the plugin's font (v1.4.9-pf.1).
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

# herdr-portal: fork pin v1.3.0-pf.1 (upstream never pushed the 1.3.0 tag)
# which keeps unknown-state panes on the board via the working column,
# on-demand only — activation must not open the board itself — with both
# keybindings in the template on the o namespace.
assert_contains "$body" "PannenetsF/herdr-portal"
assert_contains "$body" "v1.3.0-pf.1"
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

# herdr-projects board key (prefix+a): shipped in the template itself, not
# written by a post-activation `configure` (the 1.2 plugin has none).
assert_contains "config/herdr/config.toml" 'key = "prefix+a"'
assert_contains "config/herdr/config.toml" 'command = "herdr-projects.open"'
assert_contains "config/herdr/config.toml" 'type = "plugin_action"'

# Repo picker (prefix+shift+c) and the other four popup launchers.
assert_file_exists "config/herdr/new-project.sh"
assert_contains "config/herdr/config.toml" 'herdr-new-project'
assert_file_exists "config/herdr/pick-project.sh"
assert_contains "config/herdr/config.toml" 'herdr-pick-project'
# All five popup launchers are linked from the single shared
# modules/herdr-launchers.nix, imported from every host layer (macOS and
# Linux). The key bindings ship unconditionally in config.toml, so the links
# must be platform-independent — a missing one makes prefix+ctrl+p (and the
# rest of the project namespace) silently no-op on that layer.
assert_file_exists "modules/herdr-launchers.nix"
assert_contains "home.nix" "./modules/herdr-launchers.nix"
for launcher in herdr-new-project herdr-pick-project herdr-add-repo herdr-new-coordinator herdr-focus-coordinator; do
	assert_contains "modules/herdr-launchers.nix" "\".local/bin/$launcher\""
	assert_not_contains "modules/herdr.nix" "\".local/bin/$launcher\""
	assert_not_contains "modules/darwin.nix" "\".local/bin/$launcher\""
done
# Focus-coordinator (prefix+ctrl+f) ships its own binding.
assert_file_exists "config/herdr/focus-coordinator.sh"
assert_contains "config/herdr/config.toml" 'key = "prefix+ctrl+f"'
assert_contains "config/herdr/config.toml" 'herdr-focus-coordinator'
# Repo-registration picker (prefix+shift+a)
assert_file_exists "config/herdr/add-repo.sh"
assert_contains "config/herdr/config.toml" 'herdr-add-repo'

# --- 1.2 board model: registry, coordinator CLI, state.json focus ------------
#
# The plugin is pinned to UPSTREAM v1.2.13 and gated on server >= 0.9.3.
assert_contains "$body" "eliasstravik/herdr-projects"
assert_contains "$body" "v1.2.13"
assert_contains "$body" "(0, 9, 3)"
# The old fork's configure step is gone for good (radar's configure action is
# unrelated and must stay).
assert_not_contains "$body" 'configure >'
assert_not_contains "$body" "HERDR_PROJECTS_BIN"
assert_not_contains "$body" "v0.2.34-pf.2"

# Repo registration has no register-only CLI: an undelegated placeholder task
# is added (no agent starts, no herdr required) and cleared at once; the
# repos.json entry persists.
assert_contains "config/herdr/herdr-popup-lib.sh" 'add "register local repository" --repo'
assert_contains "config/herdr/herdr-popup-lib.sh" 'clear "$id"'
assert_contains "config/herdr/herdr-popup-lib.sh" "data/repos.json"

# Opening a repo goes through the public project-coordinator CLI (new on first
# use, restart when state exists but the pane is gone).
assert_contains "config/herdr/herdr-popup-lib.sh" 'coordinator --project'
assert_contains "config/herdr/new-coordinator.sh" 'coordinator --project "$repo" new'
assert_contains "config/herdr/herdr-popup-lib.sh" 'action="restart"'

# focus-coordinator is the kept local feature: state.json under
# data/coordinator/<session>/projects/<repo>/, socket pinned from the state,
# structural sw-coordinator-<repo> family fallback, plain agent focus.
assert_contains "config/herdr/herdr-popup-lib.sh" "data/coordinator"
assert_contains "config/herdr/herdr-popup-lib.sh" "projects"
assert_contains "config/herdr/herdr-popup-lib.sh" "state.json"
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_coordinator_name_head"
assert_contains "config/herdr/herdr-popup-lib.sh" "sw-coordinator-"
assert_contains "config/herdr/herdr-popup-lib.sh" 'herdr agent focus'
assert_contains "config/herdr/focus-coordinator.sh" "hp_focus_repo_coordinator"
# The 29-char head mirrors co.rs AGENT_NAME_MAX - 3 (room for the -2 suffix).
assert_contains "config/herdr/herdr-popup-lib.sh" 'full="${full:0:29}"'

# Session/socket derivation mirrors the plugin's session_name/current_socket.
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_session_name"
assert_contains "config/herdr/herdr-popup-lib.sh" "sessions/"
assert_contains "config/herdr/herdr-popup-lib.sh" "HERDR_SOCKET_PATH"

# The registry-backed fzf picker replaced the old slug list; worktree .git
# files still match (-type f alongside -type d).
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_pick_known_repo"
assert_contains "config/herdr/pick-project.sh" "hp_pick_known_repo"
assert_contains "config/herdr/herdr-popup-lib.sh" '\( -type d -o -type f \) -name .git'
assert_contains "config/herdr/add-repo.sh" "hp_filter_unknown_repos"

# The old slug/adopt machinery must be entirely gone.
assert_not_contains "config/herdr/herdr-popup-lib.sh" "hp_slug_head"
assert_not_contains "config/herdr/herdr-popup-lib.sh" "coordinator adopt"
assert_not_contains "config/herdr/herdr-popup-lib.sh" "hpc-"
assert_not_contains "config/herdr/herdr-popup-lib.sh" "HERDR_PROJECTS_ROOT"
assert_not_contains "config/herdr/herdr-popup-lib.sh" ".state/coordinator.json"
assert_not_contains "config/herdr/new-project.sh" "invalid slug"

# --- Wrapper-script hardening (PATH self-sufficiency) ------------------------
#
# All five launchers must be runnable from a bare popup environment: herdr's
# popup spawns them with a minimal PATH that lacks the HM profile and Homebrew.
# The PATH-prepend dirs live once in the shared sibling library, and every
# launcher sources that library next to its own resolved path.
assert_file_exists "config/herdr/herdr-popup-lib.sh"
assert_contains "config/herdr/herdr-popup-lib.sh" "/etc/profiles/per-user/"
assert_contains "config/herdr/herdr-popup-lib.sh" "/opt/homebrew/bin"
for s in new-project pick-project add-repo new-coordinator focus-coordinator; do
	assert_contains "config/herdr/$s.sh" "herdr-popup-lib.sh"
done

# nix-darwin: config.toml backup + diff before overwrite.
assert_contains "$body" "config.toml.bak-"
assert_contains "$body" "diff -u"

[[ -x "${repo_root}/install-herdr-plugins.sh" ]] || fail "install-herdr-plugins.sh must be executable"

echo "herdr config activation test OK"
