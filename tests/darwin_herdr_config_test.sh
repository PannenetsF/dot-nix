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

# herdr-portal: forked pinned tag. pf.1 keeps unknown-state agents visible in
# a multi-agent tab; pf.2 adds the attention (待处理) column fed by the 0.2
# projects fork's thread states. On-demand only — activation must not open the
# board itself — with both keybindings in the template on the o namespace.
assert_contains "$body" "PannenetsF/herdr-portal"
assert_contains "$body" "v1.3.0-pf.4"
assert_contains "config/herdr/config.toml" 'key = "prefix+shift+o"'
assert_contains "config/herdr/config.toml" 'command = "herdr-portal.open-board"'
assert_contains "config/herdr/config.toml" 'key = "prefix+ctrl+o"'
assert_contains "config/herdr/config.toml" 'command = "herdr-portal.open-web"'
# herdr-unread-jump: in-app toasts auto-dismiss with no sticky option, so the
# template ships a key that cycles focus to the next blocked/done pane.
assert_contains "config/herdr/config.toml" 'key = "prefix+u"'
assert_contains "config/herdr/config.toml" 'command = "to4iki.unread-jump.next"'
# The 1.2 task board's own plugin_action must NOT ship in the template (the
# 0.2 fork's overview popup is merged by configure into the writable file).
assert_not_contains "config/herdr/config.toml" 'herdr-projects.open'

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

# herdr-remote Telegram bot: second launchd user agent running relay/herdr_telegram.py
# as a WebSocket client of the loopback relay. Credentials come from machine-local
# secrets.env (never the repo); without HERDR_TG_TOKEN the wrapper exits 0 (dormant),
# so KeepAlive must not retry-loop. It needs only outbound HTTPS (long polling).
assert_contains "nix-darwin/herdr-remote.nix" "launchd.user.agents.herdrTelegram"
assert_contains "nix-darwin/herdr-remote.nix" "org.nix-community.home.herdr-telegram"
assert_contains "nix-darwin/herdr-remote.nix" "herdr_telegram.py"
assert_contains "nix-darwin/herdr-remote.nix" "secrets.env"
assert_contains "nix-darwin/herdr-remote.nix" "HERDR_TG_TOKEN"
assert_contains "nix-darwin/herdr-remote.nix" "HERDR_TG_CHAT_ID"
assert_contains "nix-darwin/herdr-remote.nix" "ws://127.0.0.1:8375"
assert_contains "nix-darwin/herdr-remote.nix" "staying dormant"

# Local out-of-tree patch on the pinned upstream source:
# 1. Telegram blocked/done notifications identify a pane as
#    "project > pane(title+pane id) > session" instead of the stock
#    "<claude> blocked in <basename cwd>".
# 2. /read, /reply and the finished excerpt are served from the agent's own
#    transcript (relay get_history -> parsed Claude/Codex/Pi/Kimi JSONL), never
#    from a raw pane capture, so TUI chrome ("Update available", spinners, the
#    input box, permission footer) never reaches Telegram; raw capture is only
#    a labelled fallback when the transcript is unavailable.
# The nix module applies it with patch(1) on a copied, writable source tree;
# a bump that drifts the upstream file makes the nix build fail loudly.
assert_file_exists "patches/herdr-remote-telegram-notifications.patch"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "agent_identity"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "effective_project"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "pane_descriptor"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "get_history"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "fetch_history"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "render_history"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "read_agent"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "last_assistant_excerpt"
assert_contains "patches/herdr-remote-telegram-notifications.patch" "transcript unavailable"
assert_contains "nix-darwin/herdr-remote.nix" "runCommandLocal"
assert_contains "nix-darwin/herdr-remote.nix" "herdr-remote-telegram-notifications.patch"

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
# All five popup launchers are linked from the single shared
# modules/herdr-launchers.nix, imported from every host layer (macOS and
# Linux). The key bindings ship unconditionally in config.toml, so the
# links must be platform-independent — a missing one makes prefix+ctrl+p
# (and the rest of the project namespace) silently no-op on that layer.
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
for s in new-project pick-project add-repo new-coordinator focus-coordinator; do
	assert_contains "config/herdr/$s.sh" "herdr-popup-lib.sh"
done

# Registered-coordinator identity (fork pf.2): the shared lib mirrors Rust
# names.rs (head() truncation widths 24/22, structural family test), and the
# two identity-aware launchers drive off those helpers.
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_slug_head"
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_pane_is_coordinator_of"
assert_contains "config/herdr/herdr-popup-lib.sh" 'hp_slug_head "$slug" 24'
assert_contains "config/herdr/herdr-popup-lib.sh" 'hp_slug_head "$slug" 22'
assert_contains "config/herdr/herdr-popup-lib.sh" "hp_adopt() {"
assert_contains "config/herdr/herdr-popup-lib.sh" "coordinator adopt"
assert_contains "config/herdr/new-coordinator.sh" "hp_adopt \"\$hp_bin\""
assert_contains "config/herdr/focus-coordinator.sh" "herdr agent focus"
assert_contains "config/herdr/focus-coordinator.sh" ".state/coordinator.json"
# The fork pin for the plugin is pf.5 in the shared activation body.
assert_contains "$body" "v0.2.34-pf.5"

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

# --- One-time rolloff from the incompatible upstream 1.2.x task-board model --
# The fork pin is permanent (project+threads/ticker model vs 1.2 task board);
# activation must unregister a present 1.2 plugin, signal only its four orphan
# helper daemons by argv (never the 0.2 ticker), then install the 0.2 fork.
assert_contains "$body" "v0.2.34-pf.5"
assert_contains "$body" "eliasstravik/herdr-projects@"
assert_contains "$body" "plugin uninstall herdr-projects"
assert_contains "$body" "(keeper|keeper-work|voice helper|serve)"
assert_contains "$body" "(0, 9, 5)"
assert_contains "$body" "HERDR_PROJECTS_BIN"
# configure falls back to the plugin action API when the $hp_bin link dangles
# on a fresh install (link-command.sh hard-codes the legacy plugins/github dir).
assert_contains "$body" "action invoke configure"
assert_contains "$body" "--plugin herdr-projects"
# 1.2-only artifacts must never reappear in the tracked files.
assert_not_contains "$body" "v1.2.13"
assert_not_contains "$body" "(0, 9, 3)"
assert_not_contains "config/herdr/herdr-popup-lib.sh" "repos.json"
# The fork builds from source (no release assets): cargo must be on the
# activation PATH in both thin wrappers.
assert_contains "nix-darwin/herdr.nix" ".cargo/bin"
assert_contains "modules/herdr.nix" ".cargo/bin"
# On macOS the HM profile ships nix gcc as `cc`, whose collect2 ld cannot
# link a darwin Rust binary (no -liconv in its sysroot); the darwin wrapper
# alone pins Apple's cc. The Linux wrapper must NOT hard-code a cc path.
assert_contains "nix-darwin/herdr.nix" "CC=/usr/bin/cc"
assert_not_contains "modules/herdr.nix" "CC="

# The IME/experimental block must survive template activations (settings-UI
# toggles were repeatedly wiped by template reinstalls).
assert_contains "config/herdr/config.toml" "switch_ascii_input_source_in_prefix = true"
assert_contains "config/herdr/config.toml" "allow_nested = true"

[[ -x "${repo_root}/install-herdr-plugins.sh" ]] || fail "install-herdr-plugins.sh must be executable"

echo "herdr config activation test OK"
