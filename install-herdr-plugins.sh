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
# needs >= 0.9.0, herdr-projects >= 0.9.3.
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
  # (working/blocked/done/idle tiers), grouping and activity ordering.
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
  # Fork pin v1.4.9-pf.1: the only patch left on top of upstream 1.4.9 is the
  # static ws_key — per-pane group keys must not carry a recency component,
  # or N panes' independent async metadata writes skew the key between retries
  # and headers land mid-group. Older pf patches (header order, fingerprint
  # hardening, projects-view coexistence) are all gone: #49 was fixed
  # upstream via view reassert/keeper, and herdr-projects 1.2.x no longer
  # installs a global agents view.
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "hhdebb.herdr-radar.*PannenetsF/herdr-radar@v1.4.9-pf.1"; then
    # Never let one plugin's install failure abort the activation: the
    # configure/state-start and projects steps below are independently guarded
    # and harmless on a partial install.
    "$herdr_cli" plugin install -y --ref v1.4.9-pf.1 \
      PannenetsF/herdr-radar || true
  fi
  "$herdr_cli" plugin action invoke configure \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true
  # Startup hooks only fire when the herdr server starts; bring the state-
  # glyph daemon up immediately so the sidebar works without a herdr restart
  # after install.
  "$herdr_cli" plugin action invoke state-start \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true

  # herdr-projects 1.2.x: the task board + per-repo project coordinators.
  # Requires server >= 0.9.3; plugin install talks to the running server and
  # fails hard against a stale one, so skip until the server is restarted.
  # Pinned to UPSTREAM eliasstravik/herdr-projects (the old 0.2.x pf fork is
  # fully retired — its registered-coordinator identity, adoption, context
  # gate and sticky-nudge patches all solve problems the 1.2 board model no
  # longer has; the one behavior upstream still lacks, focusing a repo
  # coordinator's pane across sessions, lives in the shell launchers,
  # config/herdr/focus-coordinator.sh).
  #
  # Unlike the old fork there is no `configure` step:
  #   - the prefix+a board key ships in this repo's config.toml template, so
  #     the plugin never offers to write one (and template reinstalls could
  #     not wipe it anyway);
  #   - its proposed [ui.sidebar.agents] rows are deliberately not shipped —
  #     they collide with radar's glyph table; the plugin detects radar's
  #     rows as a hand-written table and leaves them alone, and the board
  #     itself shows all three rows;
  #   - hooks/skills are maintained by the plugin's own startup hook.
  # First run archives a legacy ~/.herdr-projects from the 0.2.x model to
  # ~/.herdr-projects-legacy; the release binary is downloaded by the
  # plugin's bin/run.sh at install, no toolchain needed.
  if python3 -c 'import sys
v = sys.argv[1].split("-", 1)[0].split("+", 1)[0]
t = tuple(int(x) for x in v.split(".") if x != "")
sys.exit(0 if t >= (0, 9, 3) else 1)' "$server_version" 2>/dev/null; then
    if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "eliasstravik/herdr-projects@v1.2.13"; then
      "$herdr_cli" plugin install -y --ref v1.2.13 \
        eliasstravik/herdr-projects || true
    fi
  else
    echo >&2 "herdr server is older than 0.9.3; restart herdr to install herdr-projects"
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

  # herdr-portal: global read-mostly agent board. Pure-stdlib Python curses
  # TUI opened on demand as an overlay pane (prefix+shift+o), plus a stdlib
  # HTTP "big screen" daemon started by its own open-web action
  # (prefix+ctrl+o, 127.0.0.1:8787; 1.3.0 gates /api/* behind a loopback
  # token plus Host/Origin checks). No startup hook and no interpreter
  # prerequisites, so nothing to invoke here: the board opens only when the
  # user asks. Upstream 1.3.0 rebuilt the status system so
  # agent_status=unknown is a first-class status (label, counts, spaces
  # view), but it never gives unknown a columns bucket — collect() builds
  # only blocked/working/settled/window, and both the TUI and web board read
  # just those, so several agents freshly started in one tab all vanish from
  # the main board; idle reclaim also treated them as candidates. Our fork
  # tag v1.3.0-pf.1 (on top of the 1.3.0 release commit ba47b65 — upstream
  # never pushed a v1.3.0 tag) routes unknown cards into the working column
  # while keeping the 未知 label/count, and protects them from reclaim.
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "herdr-portal.*PannenetsF/herdr-portal@v1.3.0-pf.1"; then
    "$herdr_cli" plugin install -y --ref v1.3.0-pf.1 \
      PannenetsF/herdr-portal || true
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
