#! /usr/bin/env bash
# Shared herdr post-activation logic for BOTH nix-darwin (macOS) and Home
# Manager (Linux). Installs the writable config.toml template and the pinned
# plugin set, then repairs plugin-owned config blocks and reloads the server.
#
# This script must run AS THE TARGET USER. The macOS caller performs the
# privilege crossing once (into the user's GUI session) and invokes this whole
# script there; the Linux Home Manager activation is already user-scoped.
# Everything Mac-specific (the crossing itself, brew prefix, staff group)
# therefore stays in the nix modules, never in here.
#
# Environment:
#   HERDR_TEMPLATE       Required. Nix-store path of the config.toml template.
#   HERDR_CLI            herdr binary. Defaults to PATH lookup, then common
#                        install locations. Plugin work is skipped when absent.
#   HERDR_CONFIG_DIR     Default: $HOME/.config/herdr.
#   HERDR_PROJECTS_BIN   Default: $HOME/.local/bin/herdr-projects.
#   HERDR_ROADBOARD_SRC  Default: $HOME/Documents/workspace/roadboard.
#   HERDR_PUSH_RELAY_URL When set (http(s) URL of a herdr-remote relay), the
#                        dcolinmorgan/herdr-push plugin is pinned-installed and
#                        its .env seeded once with HERDR_RELAY=<url>. Unset on
#                        Linux: the relay is a macOS-only launchd service.
#
# Always runs as the target user (the nix-darwin caller crosses privileges into
# the user's GUI session once before invoking it), so created files are
# user-owned without any ownership fixup.
set -euo pipefail

: "${HERDR_TEMPLATE:?install-herdr-plugins.sh needs HERDR_TEMPLATE}"

config_dir="${HERDR_CONFIG_DIR:-$HOME/.config/herdr}"
hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
roadboard_src="${HERDR_ROADBOARD_SRC:-$HOME/Documents/workspace/roadboard}"

if [ -n "${HERDR_CLI:-}" ] && [ -x "$HERDR_CLI" ]; then
  herdr_cli="$HERDR_CLI"
else
  # Official Linux installs land outside the Nix profile (kept independent on
  # purpose), so probe PATH plus the usual install locations.
  herdr_cli=""
  for candidate in herdr "$HOME/.local/bin/herdr" /usr/local/bin/herdr; do
    if command -v "$candidate" >/dev/null 2>&1; then
      herdr_cli="$(command -v "$candidate")"
      break
    fi
  done
fi

# herdr rewrites this file itself (settings UI, theme selection), so it is
# installed as a writable regular file like the AeroSpace config, not as a
# read-only Home Manager symlink into the Nix store. Activation overwrites the
# live file with this template every run; before that, local edits are backed
# up (config.toml.bak-<timestamp>, last 5 kept) and the diff printed.
echo >&2 "herdr config..."
install -d "$config_dir"
live="$config_dir/config.toml"
if [ -f "$live" ] && [ ! -L "$live" ]; then
  bak="$live.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$live" "$bak"
  echo >&2 "herdr config.toml local changes being overwritten (backup: $bak):"
  # diff exits 1 when files differ; that is the expected case here.
  diff -u "$live" "$HERDR_TEMPLATE" >&2 || true
  # keep only the 5 newest backups
  # shellcheck disable=SC2012
  ls -t "$live".bak-* 2>/dev/null | tail -n +6 | while IFS= read -r old; do
    rm -f -- "$old"
  done
fi
# Drop any Home Manager-managed symlink from older generations first: `cp`
# (below) would otherwise dereference it into the read-only Nix store.
rm -f "$live"
cp "$HERDR_TEMPLATE" "$live"
chmod 0644 "$live"

# The template can land without a herdr binary (fresh container, server not
# installed yet): install plugins on a later activation once herdr exists.
if [ -z "$herdr_cli" ]; then
  echo >&2 "herdr CLI not found; wrote config template, skipping plugin install"
  exit 0
fi

# herdr has no declarative plugin config, so install plugins here, pinned to
# refs. `plugin install` re-installs even when current, so guard on the
# installed ref.
if ! "$herdr_cli" plugin list 2>/dev/null | grep -q "furkankly.zoetrope.*@2d226f7"; then
  # Tolerated: a transient install failure must not skip the rest of the
  # plugin set (radar/projects have their own version gates below).
  # Source spec is OWNER/REPO[/SUBDIR]: the repo is furkankly/zoetrope and the
  # plugin manifest lives in its herdr-plugin/ subdirectory. The older dotted
  # shorthand "furkankly.zoetrope/herdr-plugin" resolved to the same repo in
  # early herdr builds but 404s on current servers (it parses as a repo named
  # herdr-plugin under owner furkankly.zoetrope).
  "$herdr_cli" plugin install -y \
    --ref 2d226f7eae7cf7b89fb7665300c419c21a6366b7 \
    furkankly/zoetrope/herdr-plugin || true
fi

# Version gates: plugin install talks to the running server and fails hard
# against one too old to know the plugin's manifest features. herdr-radar
# needs >= 0.9.0, herdr-projects >= 0.9.1.
status_json="$("$herdr_cli" status --json 2>/dev/null || true)"
# One status call feeds both gates. Python exits 0 = >= 0.9.0, 1 = older,
# 2 = version unobtainable (server down / bad payload). Suffixes like
# "-rc1" / "+build" are stripped before comparing so a prerelease tag does not
# crash int() and masquerade as "older".
if printf '%s' "$status_json" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)["server"]["version"]
    v = v.split("-", 1)[0].split("+", 1)[0]
    t = tuple(int(x) for x in v.split(".") if x != "")
    sys.exit(0 if t >= (0, 9, 0) else 1)
except Exception:
    sys.exit(2)
'; then
  server_version="$(printf '%s' "$status_json" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["server"]["version"])' 2>/dev/null || true)"

  # herdr-radar rewrites the sidebar Agents list with per-agent state glyphs
  # (working/blocked/done/idle tiers), project grouping and activity ordering.
  # It is a Node plugin: its interpreter is nodejs_22 from host.nix (macOS
  # builds take node from the PATH the nix-darwin activation prepends). Its
  # install build hook and daemon manage three marker-fenced blocks (tab-bar
  # command, [ui.sidebar.*], [theme.custom]) plus the per-user icon font —
  # none of which are in the repo template. The template reinstall above WIPES
  # those blocks every run, so re-invoke configure afterwards to repair them.
  # Ordering caveat: Home Manager has already swapped kitty.conf to the new
  # generation by the time this runs, and config/kitty/kitty.conf ships the
  # plugin's exact font codepoint-map block — otherwise the build hook
  # hard-fails writing through the read-only Nix-store symlink (its setup.js
  # is not EACCES-safe).
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "hhdebb.herdr-radar.*PannenetsF/herdr-radar@v1.4.4-pf.6"; then
    # Never let one plugin's install failure abort the activation: the
    # configure/state-start and projects steps below are independently guarded
    # and harmless on a partial install.
    "$herdr_cli" plugin install -y --ref v1.4.4-pf.6 \
      PannenetsF/herdr-radar || true
  fi
  "$herdr_cli" plugin action invoke configure \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true
  # Startup hooks only fire when the herdr server starts; bring the state-
  # glyph daemon up immediately so the sidebar works without a herdr restart
  # after install.
  "$herdr_cli" plugin action invoke state-start \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true

  # herdr-projects requires server >= 0.9.1; plugin install talks to the
  # running server and fails hard against a stale one, so skip until the
  # server is restarted.
  if python3 -c 'import sys
v = sys.argv[1].split("-", 1)[0].split("+", 1)[0]
t = tuple(int(x) for x in v.split(".") if x != "")
sys.exit(0 if t >= (0, 9, 1) else 1)' "$server_version" 2>/dev/null; then
    # Fork pin: upstream 0.2.34 drops untracked panes into the global "other"
    # tail, which tears a workspace in two when a second harness (e.g. codex)
    # works in a tracked project folder. The fork claims them into the
    # project's hp_group block.
    if ! "$herdr_cli" plugin list 2>/dev/null \
        | grep -q "PannenetsF/herdr-projects@v0.2.34-pf.1"; then
      "$herdr_cli" plugin install -y --ref v0.2.34-pf.1 \
        PannenetsF/herdr-projects || true
    fi
    # Sidebar grouping rows, the prefix+a popup and tab-bar entry are NOT in
    # the repo template: full configure adds them to the writable live config
    # after the template lands (and journals them so the plugin's doctor
    # validates them). It also maintains the agent progress hooks and
    # autoproject skill links. Idempotent, and repairs hooks lost to other
    # tools rewriting the agents' settings files.
    if [ -x "$hp_bin" ]; then
      "$hp_bin" configure >/dev/null 2>&1 || true
    fi
  else
    echo >&2 "herdr server is older than 0.9.1; restart herdr to install herdr-projects"
  fi

  # herdr-web-ui: browser/PWA client over the herdr socket API (workspaces,
  # tabs, panes, chat and live terminal at http://127.0.0.1:7317). Bun plugin
  # whose build hook needs bun >= 1.4 and node >= 18 on PATH (both in the host
  # package set); it defaults to loopback only. Its startup hook brings the
  # bridge up when the herdr server starts — invoke its start action here as
  # well so a freshly installed plugin works without a herdr restart (same
  # rationale as radar's state-start).
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "devswha.herdr-web-ui.*@v0.4.11"; then
    "$herdr_cli" plugin install -y --ref v0.4.11 \
      devswha/herdr-web-ui || true
  fi
  "$herdr_cli" plugin action invoke start \
    --plugin devswha.herdr-web-ui >/dev/null 2>&1 || true

  # herdr-portal: global read-mostly agent board (loofare/herdr-portal).
  # Pure-stdlib Python curses TUI opened on demand as an overlay pane
  # (prefix+shift+o), plus a stdlib HTTP "big screen" daemon started by its
  # own open-web action (prefix+ctrl+o, 127.0.0.1:8787). No startup hook and
  # no interpreter prerequisites, so nothing to invoke here: the board opens
  # only when the user asks. Upstream has no tag past v1.0.3, so pin the full
  # commit of the v1.2.0 release, like herdr-push.
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "herdr-portal.*loofare/herdr-portal@cae8ea0"; then
    "$herdr_cli" plugin install -y \
      --ref cae8ea07a51f54d6e73b6e5a40d0930c8d4f074f \
      loofare/herdr-portal || true
  fi

  # herdr-push: emits pane.agent_status_changed events to a herdr-remote relay
  # for the Herdi menu-bar app / phone / Telegram clients. Pure shell+curl;
  # only installed when the platform layer supplies a relay URL (the macOS
  # wrapper passes the loopback relay; the Linux wrapper passes nothing).
  push_relay_url="${HERDR_PUSH_RELAY_URL:-}"
  if [ -n "$push_relay_url" ]; then
    if ! "$herdr_cli" plugin list 2>/dev/null \
        | grep -q "herdr.push.*dcolinmorgan/herdr-push@f4fdb06"; then
      "$herdr_cli" plugin install -y \
        --ref f4fdb06d5413ac2d96ca225ea33f288f41bfc001 \
        dcolinmorgan/herdr-push || true
    fi
    # Seed the relay URL once into the plugin's own .env (on_event.sh reads
    # HERDR_PLUGIN_CONFIG_DIR/.env). Never overwrite: switching to a tunnel URL
    # later is a local, user-owned edit, like config.toml/local.zsh.
    push_cfg_dir="$("$herdr_cli" plugin config-dir herdr.push 2>/dev/null || true)"
    if [ -n "$push_cfg_dir" ] && [ -d "$push_cfg_dir" ] && [ ! -e "$push_cfg_dir/.env" ]; then
      printf 'HERDR_RELAY=%s\n' "$push_relay_url" >"$push_cfg_dir/.env"
      chmod 0600 "$push_cfg_dir/.env"
    fi
  fi
else
  rc=$?
  if [ "$rc" = 2 ]; then
    echo >&2 "herdr server version unavailable (is herdr running?); skipping plugin install/configure this run"
  else
    echo >&2 "herdr server is older than 0.9.0; restart herdr to install pinned plugins"
  fi
fi

# roadboard: local development plugin (7-state Obsidian roadmap tree). Linked
# from a local checkout, not a remote GitHub pin; only ensure the link exists
# when the repo is present, and never fail activation on it.
if [ -d "$roadboard_src" ] && [ -f "$roadboard_src/herdr-plugin.toml" ]; then
  if ! "$herdr_cli" plugin list 2>/dev/null | grep -q '"plugin_id":"roadboard"'; then
    "$herdr_cli" plugin link "$roadboard_src" >/dev/null 2>&1 || true
  fi
fi

"$herdr_cli" server reload-config 2>/dev/null || true
