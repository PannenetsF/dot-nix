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
#   HERDR_AGENT_INTEGRATIONS
#                        Space-separated list of built-in agent integrations
#                        (e.g. "claude codex") ensured on every activation via
#                        `herdr integration install <name>`. The installer is a
#                        purely local, idempotent file write and self-gates with
#                        rc=1 when the agent's own config directory does not
#                        exist, so wrappers pass the full desired list without
#                        probing what is installed. Unset: nothing is ensured.
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

# Built-in agent integrations: session-reporting hooks herdr merges into each
# agent's own config directory (~/.claude/hooks/herdr-agent-state.sh,
# ~/.codex/herdr-agent-state.sh + a SessionStart hook entry), so herdr can map
# a pane to the agent session running inside it (radar glyphs, zoetrope,
# transcript reads and portal all depend on that session id). Unlike the
# plugins below, `integration install` is a purely local, network-free file
# merge: it is idempotent (no-op while the bundled integration version is
# current, upgrades when outdated) and self-gates with rc=1 when the agent's
# config directory does not exist, so wrappers pass the full desired list on
# every platform without probing what is installed. It also never talks to
# the running server, hence it stays OUTSIDE the version gate below; running
# it on every activation repairs the hook when another tool rewrites the
# agent's settings file (same recovery rationale as projects' configure).
for integration in ${HERDR_AGENT_INTEGRATIONS:-}; do
  "$herdr_cli" integration install "$integration" >/dev/null 2>&1 || true
done

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

# herdr-unread-jump: herdr hard-codes the in-app toast display time
# (8s needs-attention / 5s finished; there is no sticky/persistent option),
# so after a toast auto-dismisses this action focuses the next pane that
# still needs handling: blocked first, then done, wrapping within the group.
# Pure bash+jq (jq is in the host package set), min herdr 0.7.5 — like
# zoetrope it installs OUTSIDE the >= 0.9.0 server-version gate below.
# Upstream ships no tags, so pin the commit SHA.
if ! "$herdr_cli" plugin list 2>/dev/null | grep -q "to4iki.unread-jump.*@be4cd1f"; then
  "$herdr_cli" plugin install -y \
    --ref be4cd1fecf9bf0684a0fe0f2dd1c2316bf819389 \
    to4iki/herdr-unread-jump || true
fi

# Version gates: plugin install talks to the running server and fails hard
# against one too old to know the plugin's manifest features. herdr-radar
# needs >= 0.9.0, herdr-projects >= 0.9.5 (pf.5 caller identity queries
# `pane process-info`, which only 0.9.5 servers answer).
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
  # Fork pin v1.4.9-pf.2 on top of upstream 1.4.9: (1) the static ws_key —
  # per-pane group keys must not carry a recency component, or N panes'
  # independent async metadata writes skew the key between retries and
  # headers land mid-group; (2) herdr-projects coexistence — Herdr holds ONE
  # global agent view and this daemon re-asserts its own every 15s, so while
  # that plugin is enabled radar installs its exact spec (hp_role guest/other
  # hiding filter + hp_group/hp_rank order) and pins one header per PROJECT
  # (slug parsed from hp_group; each thread lives in its own worktree
  # workspace, so workspace/repo headers misplace them). The projects probe
  # is fail-sticky: a failed `plugin list` spawn keeps the last answer, never
  # flashes the unfiltered view in. projects configure merges its entries
  # into radar's marker-fenced blocks, so the two must be called in this
  # order: radar first, projects second.
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "hhdebb.herdr-radar.*PannenetsF/herdr-radar@v1.4.9-pf.2"; then
    # Never let one plugin's install failure abort the activation: the
    # configure/state-start and projects steps below are independently guarded
    # and harmless on a partial install.
    "$herdr_cli" plugin install -y --ref v1.4.9-pf.2 \
      PannenetsF/herdr-radar || true
  fi
  "$herdr_cli" plugin action invoke configure \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true
  # Startup hooks only fire when the herdr server starts; bring the state-
  # glyph daemon up immediately so the sidebar works without a herdr restart
  # after install.
  "$herdr_cli" plugin action invoke state-start \
    --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true

  # herdr-projects: project + thread model with a persistent ticker daemon.
  # Requires server >= 0.9.5; plugin install talks to the running server and
  # fails hard against a stale one, so skip until the server is restarted.
  # Pinned to fork v0.2.34-pf.5 (PannenetsF/herdr-projects): registered
  # coordinator identity (`hpc-<slug>` family names), adoption of
  # hand-started sessions, context registration gate, session-sticky nudges
  # and the untracked-pane claim for a second harness in a tracked project
  # folder. pf.3 fixes a badge gap: a launch that gave up (failed status)
  # left the ticker scan before persisting a group, so the needs-you badge
  # (which reads last_group) lagged the live rows/portal by one and the
  # failure never rang — failed launches are now recorded waiting-on-you and
  # announce exactly once. pf.4 adds the sidebar audience contract: every
  # pane is stamped hp_role (coordinator/thread/guest/other) + hp_audience
  # (human/internal/stalled), the default agents view hides guest/other via a
  # not-in filter radar mirrors, a blocked thread upgrades to stalled after
  # HERDR_PROJECTS_STALL_UPGRADE_SECS, and the ticker no longer evicts a
  # project's layout part when one thread's pass errors (header flicker) or
  # rewrites no-project keys every tick (~!<pane_id> is stable now).
  # pf.5 closes the caller-identity hole: HERDR_ENV markers and the
  # env-supplied socket/binary are fully attacker-controlled, so identity is
  # proven from process-table ancestry/process-group facts cross-checked
  # against a genuine herdr binary (fixed absolute paths under the real home
  # and system prefixes, never PATH/HERDR_BIN_PATH) talking ONLY to sessions
  # in the real-home registry. Any process-fact-proven pane without an
  # accountable agent row fails closed (Unverified), so an agent cannot
  # `pane run` a stripped command to act as a person.
  # The 0.2 model uses project slugs with per-project
  # home directories (`~/.herdr-projects/<slug>/`); the ticker is its ONLY
  # bell source — herdr notification show --sound request/done when threads
  # enter waiting-on-you / ready-for-review. The upstream 1.2.x task-board
  # model is incompatible (no thread states, no ticker bells, repo registry
  # format differs), so this pin is permanent — DO NOT upgrade to 1.2.x.
  #
  # Sidebar rows, the prefix+a overview popup and tab-bar entries are NOT in
  # the repo template: configure adds them to the writable live config after
  # the template lands. It also merges into radar's existing marker-fenced
  # blocks, which is why radar configure must run first. Configure is
  # idempotent and repairs hooks/config lost to other tools rewriting the
  # agents' settings files.
  if python3 -c 'import sys
v = sys.argv[1].split("-", 1)[0].split("+", 1)[0]
t = tuple(int(x) for x in v.split(".") if x != "")
sys.exit(0 if t >= (0, 9, 5) else 1)' "$server_version" 2>/dev/null; then
    # Fork pin v0.2.34-pf.5 (see block comment above).
    installed_projects="$("$herdr_cli" plugin list 2>/dev/null || true)"
    if ! printf '%s' "$installed_projects" \
        | grep -q "PannenetsF/herdr-projects@v0.2.34-pf.5"; then
      # One-time rolloff window from the incompatible upstream 1.2.x
      # task-board plugin: the plugin id must be free before the 0.2 fork can
      # register, and 1.2 leaves four orphan daemons running forever
      # (keeper / keeper-work / voice helper / serve). Their argv is
      # `herdr-projects-<os>-<arch> <role>`; the regex matches exactly those
      # four roles — the 0.2 ticker's argv is `herdr-projects --root … ticker
      # run` (binary has no -<os>-<arch> suffix) and project-local watchers
      # (e.g. status_watch.py) never match. pgrep/pkill are platform-neutral
      # userland on both macOS and Linux; this never touches the ticker.
      if printf '%s' "$installed_projects" \
          | grep -q "eliasstravik/herdr-projects@"; then
        echo >&2 "herdr-projects: removing incompatible upstream 1.2.x plugin"
        "$herdr_cli" plugin uninstall herdr-projects >/dev/null 2>&1 || true
        pkill -TERM -f \
          'herdr-projects-[a-z0-9._-]+ (keeper|keeper-work|voice helper|serve)' \
          2>/dev/null || true
      fi
      # No release assets on the fork: the server builds from source with the
      # user's cargo (darwin wrapper and modules/herdr.nix both prepend
      # ~/.cargo/bin). A build failure must not abort activation.
      "$herdr_cli" plugin install -y --ref v0.2.34-pf.5 \
        PannenetsF/herdr-projects || true
    fi
    # configure merges the sidebar/tab-bar blocks into radar's marker blocks
    # (radar configure ran above). On a fresh install the $hp_bin link can be
    # dangling (older link-command.sh hard-codes the legacy plugins/github
    # layout; >= 0.9.5 installs under github-installations), so fall back to
    # invoking configure through the plugin action API.
    if [ -x "$hp_bin" ] && "$hp_bin" configure >/dev/null 2>&1; then
      :
    else
      "$herdr_cli" plugin action invoke configure \
        --plugin herdr-projects >/dev/null 2>&1 || true
    fi
  else
    echo >&2 "herdr server is older than 0.9.5; restart herdr to install herdr-projects pf.5"
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
  # (on top of the 1.3.0 release commit ba47b65 — upstream never pushed a
  # v1.3.0 tag) carries three patches: pf.1 routes unknown cards into the
  # working column while keeping the 未知 label/count and protects them from
  # reclaim; pf.2 adds the "attention" (待处理) leftmost column fed by the
  # pinned herdr-projects 0.2 fork's thread states (waiting-on-you /
  # ready-for-review via `herdr-projects thread list <slug> --json`, root
  # auto-discovered from ~/.herdr-projects with ~/.herdr-projects-legacy
  # fallback), so the session the ticker rang for is always visible —
  # live pane rows are marked and moved there, dead threads get virtual
  # cards whose Enter runs `thread restart`. pf.3 retries `agent focus`
  # for 10s after a restart: the new pane exists before its agent
  # registers, so the first focus otherwise fails "target not found" and
  # the card shows 跳转失败. pf.4 makes the board a true notification
  # center: attention is gated on a per-pane seen store
  # (~/.local/state/herdr-portal/seen.json, keyed to state_change_seq at
  # focus time) so a card leaves attention once viewed and re-enters only on
  # the next state change; coordinator-only internal confirmation points
  # (hp_audience=internal) never enter attention; stalled (>10min blocked,
  # hp_audience=stalled) still does; and saved SSH machines are aggregated
  # with [machine] labels, offline snapshots and (machine,pane) card uids.
  # The portal probes for a 0.2.x binary only; a
  # 1.2.x binary is explicitly ignored (incompatible model).
  if ! "$herdr_cli" plugin list 2>/dev/null \
      | grep -q "herdr-portal.*PannenetsF/herdr-portal@v1.3.0-pf.4"; then
    "$herdr_cli" plugin install -y --ref v1.3.0-pf.4 \
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

# Keep this after both configure calls: projects owns an older default view,
# while Radar's renderer and keeper must agree on the user-facing session list.
repo_list_installer="${HERDR_REPO_LIST_INSTALLER:-$(dirname "$0")/config/herdr/install-projects-repo-list.cjs}"
repo_list_patch="${HERDR_REPO_LIST_PATCH:-$(dirname "$0")/patches/herdr-projects-multiline-repos.patch}"
if command -v node >/dev/null 2>&1 && [ -f "$repo_list_installer" ] && [ -f "$repo_list_patch" ]; then
  node "$repo_list_installer" "$config_dir" "$repo_list_patch" \
    || echo >&2 "herdr Projects multiline repo list could not be installed"
fi
sidebar_installer="${HERDR_SIDEBAR_INSTALLER:-$(dirname "$0")/config/herdr/install-sidebar-policy.cjs}"
sidebar_policy="${HERDR_SIDEBAR_POLICY:-$(dirname "$0")/config/herdr/sidebar-policy.cjs}"
if command -v node >/dev/null 2>&1 && [ -f "$sidebar_installer" ] && [ -f "$sidebar_policy" ]; then
  HERDR_BIN_PATH="$herdr_cli" node "$sidebar_installer" "$config_dir" "$sidebar_policy" --activate \
    || echo >&2 "herdr session sidebar policy could not be activated"
fi

"$herdr_cli" server reload-config 2>/dev/null || true
