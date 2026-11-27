#!/usr/bin/env bash
# Behavior tests for install-herdr-plugins.sh: the shared herdr post-activation
# body used by nix-darwin (macOS) and Home Manager (Linux). A stub `herdr`
# records its argv; nothing here touches the real config or server.
set -euo pipefail

# Never inherit a real CLI override into the stubbed activation cases.
unset HERDR_CLI

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Stub herdr: append every invocation to $STUB_LOG. Replies are chosen by the
# STUB_MODE env the individual scenarios export.
make_stub() {
  local dir="$1"
  mkdir -p "$dir/bin"
  cat >"$dir/bin/herdr" <<'SH'
#!/usr/bin/env bash
if [ -n "${OVIS_FROM_SOURCE:-}" ]; then
  printf 'OVIS_FROM_SOURCE=%s ' "$OVIS_FROM_SOURCE" >>"$STUB_LOG"
fi
printf '%q ' "$@" >>"$STUB_LOG"
printf '\n' >>"$STUB_LOG"
case "$1" in
  status)
    if [ "$STUB_MODE" = down ]; then
      echo '{}'
    else
      printf '{"server":{"version":"%s"}}\n' "$STUB_VERSION"
    fi
    ;;
  plugin)
    case "$2" in
      list)
        if [ "${3:-}" = "--json" ]; then
          # STUB_NO_JSON=1 simulates a pre-JSON herdr that cannot name the
          # active install; the activation must then fall back to scanning the
          # known plugin directory layouts itself.
          if [ "${STUB_NO_JSON:-}" = 1 ]; then
            echo 'plugin list: unknown option'
          elif [ -n "${STUB_PROJECTS_ROOT:-}" ] || [ -n "${STUB_ROADBOARD_ROOT:-}" ]; then
            entries=()
            if [ -n "${STUB_PROJECTS_ROOT:-}" ]; then
              owner="${STUB_PROJECTS_OWNER:-PannenetsF}"
              entries+=("$(printf '{"plugin_id":"herdr-projects","plugin_root":"%s","source":{"kind":"github","owner":"%s","repo":"herdr-projects","managed_path":"%s"}}' \
                "$STUB_PROJECTS_ROOT" "$owner" "$STUB_PROJECTS_ROOT")")
            fi
            if [ -n "${STUB_ROADBOARD_ROOT:-}" ]; then
              rb_owner="${STUB_ROADBOARD_OWNER:-PannenetsF}"
              entries+=("$(printf '{"plugin_id":"roadboard","plugin_root":"%s","source":{"kind":"github","owner":"%s","repo":"roadboard","managed_path":"%s"}}' \
                "$STUB_ROADBOARD_ROOT" "$rb_owner" "$STUB_ROADBOARD_ROOT")")
            fi
            joined="$(IFS=,; printf '%s' "${entries[*]}")"
            printf '{"type":"plugin_list","result":{"plugins":[%s]}}\n' "$joined"
          else
            echo '{"type":"plugin_list","result":{"plugins":[]}}'
          fi
        # STUB_PLUGIN_LIST lets a test supply arbitrary multi-line `plugin list`
        # output (e.g. legacy web-ui, local links, or already-pinned plugins).
        elif [ -n "${STUB_PLUGIN_LIST:-}" ]; then
          printf '%s\n' "$STUB_PLUGIN_LIST"
        # STUB_PROJECTS_PIN simulates an already-registered projects plugin,
        # e.g. eliasstravik/herdr-projects@v1.2.13 for the rolloff case.
        elif [ -n "${STUB_PROJECTS_PIN:-}" ]; then
          printf -- '- herdr-projects (Projects) enabled [github:%s]\n' "$STUB_PROJECTS_PIN"
        else
          echo '[]'
        fi
        ;;
      install)
        if [ -n "${STUB_FAIL_INSTALL_REPO:-}" ] && printf '%s\n' "$@" | grep -Fqx "$STUB_FAIL_INSTALL_REPO"; then
          exit 1
        fi
        ;;
      config-dir)
        # Real herdr prints the plugin's config dir and creates it on demand.
        d="$HOME/.config/herdr/plugins/config/$3"
        mkdir -p "$d"
        printf '%s\n' "$d"
        ;;
    esac
    ;;
  integration)
    # The real installer self-gates with rc=1 ("install codex first") when
    # the target agent's config directory does not exist.
    [ "${STUB_INTEGRATION_FAIL:-}" = 1 ] && exit 1
    ;;
esac
exit 0
SH
  # Stub pkill so the 1.2 rolloff case never signals real daemons on the test
  # machine; log argv for pattern assertions.
  cat >"$dir/bin/pkill" <<'SH'
#!/usr/bin/env bash
printf 'pkill ' >>"$STUB_LOG"
printf '%q ' "$@" >>"$STUB_LOG"
printf '\n' >>"$STUB_LOG"
exit 0
SH
  chmod +x "$dir/bin/herdr" "$dir/bin/pkill"
}

template="$tmp/template.toml"
printf '# herdr template marker = 1\n' >"$template"

run_case() {
  local home="$1"; shift
  rm -rf "$home"; mkdir -p "$home"
  (
    export HOME="$home"
    export STUB_LOG="$home/calls.log"
    export HERDR_TEMPLATE="$template"
    export HERDR_CONFIG_DIR="$home/.config/herdr"
    export HERDR_PROJECTS_BIN="$home/nonexistent-herdr-projects"
    export HERDR_ROADBOARD_BIN="$home/nonexistent-roadboard"
    export HERDR_OVIS_RESTART_DELAY=0
    # Wrappers pass the full desired agent-integration list on every platform;
    # the installer self-gates when an agent directory is absent.
    export HERDR_AGENT_INTEGRATIONS="claude codex"
    "$@"
  )
}

# --- Case 1: fresh machine, server 0.9.5 -> template + every pinned plugin --
stub1="$tmp/stub1"; make_stub "$stub1"; home1="$tmp/home1"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  HERDR_PUSH_RELAY_URL=http://127.0.0.1:8375 \
  run_case "$home1" env PATH="$stub1/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"

[ -f "$home1/.config/herdr/config.toml" ] || fail "template not installed"
grep -q "marker = 1" "$home1/.config/herdr/config.toml" || fail "template content wrong"
[ ! -L "$home1/.config/herdr/config.toml" ] || fail "config must be a regular file, not symlink"

log1="$(cat "$home1/calls.log")"
# Agent integrations are ensured on every activation (local file merge, no
# server/network), so panes always carry their session id for radar/zoetrope.
echo "$log1" | grep -q "integration install claude" \
  || fail "claude agent integration not ensured"
echo "$log1" | grep -q "integration install codex" \
  || fail "codex agent integration not ensured"
echo "$log1" | grep -q "furkankly/zoetrope/herdr-plugin" || fail "zoetrope not installed"
echo "$log1" | grep -q "plugin install -y --ref be4cd1fecf9bf0684a0fe0f2dd1c2316bf819389 to4iki/herdr-unread-jump" \
  || fail "herdr-unread-jump not installed at the pinned ref"
echo "$log1" | grep -q "plugin install -y --ref v1.4.9-pf.3 PannenetsF/herdr-radar" \
  || fail "radar not installed at the pinned fork ref"
echo "$log1" | grep -q "PannenetsF/herdr-projects" || fail "projects not installed"
echo "$log1" | grep -q "server reload-config" || fail "server config not reloaded"

# radar configure must precede projects install (marker-block ownership order).
radar_cfg=$(echo "$log1" | grep -n "action invoke configure" | head -1 | cut -d: -f1)
proj_inst=$(echo "$log1" | grep -n "plugin install -y --ref v0.2.34-pf.17" | head -1 | cut -d: -f1)
[ -n "$radar_cfg" ] && [ -n "$proj_inst" ] && [ "$radar_cfg" -lt "$proj_inst" ] \
  || fail "radar configure ($radar_cfg) must run before projects install ($proj_inst)"

# state-start is invoked so the glyph daemon comes up without a server restart.
echo "$log1" | grep -q "action invoke state-start" || fail "radar state-start missing"

# ovis (devswha.ovis): pinned fork install from source + immediate bridge start
# (startup hooks only fire on server start).
echo "$log1" | grep -q "OVIS_FROM_SOURCE=1 plugin install -y --ref pf/0.5.11-1 PannenetsF/ovis" \
  || fail "ovis not installed at the pinned fork ref with OVIS_FROM_SOURCE=1"
echo "$log1" | grep -q "action invoke start --plugin devswha.ovis" \
  || fail "ovis start action missing"

# roadboard: pinned remote GitHub install inside the >= 0.9.5 gate.
echo "$log1" | grep -q "plugin install -y --ref v0.1.0-pf.1 PannenetsF/roadboard" \
  || fail "roadboard not installed at the pinned remote ref"
echo "$log1" | grep -q "plugin link" \
  && fail "roadboard must not use local plugin link" || true

# herdr-portal: forked pinned tag. pf.1 keeps agent_status=unknown panes
# visible (upstream gives them no column bucket); pf.2 adds the attention
# column fed by the 0.2 projects fork's thread states. Installed on every
# platform; it opens on demand, so no action is invoked by activation.
echo "$log1" | grep -q "plugin install -y --ref v1.3.0-pf.4 PannenetsF/herdr-portal" \
  || fail "herdr-portal not installed at the pinned fork ref"
echo "$log1" | grep -q "herdr-portal.open" \
  && fail "portal opens on user request only; activation must not invoke it" || true

# projects configure: HERDR_PROJECTS_BIN points at a nonexistent path in this
# harness, so activation must fall back to the plugin action API; it has to
# run after radar configure (marker-block merge order).
echo "$log1" | grep -q "action invoke configure --plugin herdr-projects" \
  || fail "projects configure action fallback missing"
proj_cfg=$(echo "$log1" | grep -n "action invoke configure --plugin herdr-projects" \
  | head -1 | cut -d: -f1)
[ -n "$radar_cfg" ] && [ -n "$proj_cfg" ] && [ "$radar_cfg" -lt "$proj_cfg" ] \
  || fail "radar configure ($radar_cfg) must run before projects configure ($proj_cfg)"

# herdr-push: pinned install, .env seeded once with the relay URL, mode 0600.
echo "$log1" | grep -q "plugin install -y --ref f4fdb06d5413ac2d96ca225ea33f288f41bfc001 dcolinmorgan/herdr-push" \
  || fail "herdr-push not installed at the pinned ref"
push_env1="$home1/.config/herdr/plugins/config/herdr.push/.env"
[ -f "$push_env1" ] || fail "herdr-push .env not seeded"
grep -Fxq "HERDR_RELAY=http://127.0.0.1:8375" "$push_env1" \
  || fail "herdr-push .env has wrong contents: $(cat "$push_env1")"
perm1="$(stat -c '%a' "$push_env1" 2>/dev/null || stat -f '%Lp' "$push_env1")"
[ "$perm1" = "600" ] || fail "herdr-push .env must be mode 0600, got $perm1"

# --- Case 2: no herdr binary -> template lands, plugins skipped, exit 0 -----
home2="$tmp/home2"; mkdir -p "$home2"
(
  # PATH alone does not hide the installer's /usr/local/bin fallback.
  # Stub discovery too, so this case cannot invoke an installed real daemon.
  command() {
    if [ "${1:-}" = -v ] && [ "${2##*/}" = herdr ]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  run_case "$home2" env PATH="/usr/bin:/bin" \
    bash "$repo_root/install-herdr-plugins.sh"
)
[ -f "$home2/.config/herdr/config.toml" ] || fail "template should land without herdr"
[ ! -e "$home2/calls.log" ] || fail "no herdr calls expected when binary absent"

# --- Case 3: server down (bad status payload) -> plugins skipped ------------
stub3="$tmp/stub3"; make_stub "$stub3"; home3="$tmp/home3"
STUB_MODE=down HERDR_PUSH_RELAY_URL=http://127.0.0.1:8375 \
  run_case "$home3" env PATH="$stub3/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log3="$(cat "$home3/calls.log")"
# zoetrope installs before the status gate (unchanged from the original
# activation); the gated radar/projects/web-ui/push set must not install while
# the server version is unobtainable.
echo "$log3" | grep -q "furkankly/zoetrope/herdr-plugin" || fail "zoetrope installs before the version gate"
echo "$log3" | grep -q "to4iki/herdr-unread-jump" || fail "unread-jump installs before the version gate (min herdr 0.7.5)"
# Integrations are a purely local file merge and never query the server, so
# they must still be ensured while the server version is unobtainable.
echo "$log3" | grep -q "integration install codex" \
  || fail "agent integrations must install outside the server-version gate"
echo "$log3" | grep -q "PannenetsF/herdr-radar" && fail "radar needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "PannenetsF/herdr-projects" && fail "projects needs a reachable >=0.9.5 server" || true
echo "$log3" | grep -q "PannenetsF/roadboard" && fail "roadboard needs a reachable >=0.9.5 server" || true
echo "$log3" | grep -q "PannenetsF/ovis" && fail "ovis needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "PannenetsF/herdr-portal" && fail "portal installs inside the version gate" || true
echo "$log3" | grep -q "dcolinmorgan/herdr-push" && fail "push must wait for a reachable server" || true
[ ! -e "$home3/.config/herdr/plugins/config/herdr.push/.env" ] \
  || fail "push .env must not be seeded when the plugin did not install"
echo "$log3" | grep -q "server reload-config" || fail "reload-config should still run"

# --- Case 4: server 0.9.0 -> radar/ovis allowed, projects/roadboard gated out
stub4="$tmp/stub4"; make_stub "$stub4"; home4="$tmp/home4"
STUB_MODE=ok STUB_VERSION=0.9.0 \
  run_case "$home4" env PATH="$stub4/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log4="$(cat "$home4/calls.log")"
echo "$log4" | grep -q "PannenetsF/herdr-radar" || fail "radar allowed on 0.9.0"
echo "$log4" | grep -q "PannenetsF/herdr-projects" && fail "projects needs >= 0.9.5" || true
echo "$log4" | grep -q "PannenetsF/roadboard" && fail "roadboard needs >= 0.9.5" || true
echo "$log4" | grep -q "OVIS_FROM_SOURCE=1 plugin install -y --ref pf/0.5.11-1 PannenetsF/ovis" \
  || fail "ovis allowed on 0.9.0 (min_herdr_version)"
# No HERDR_PUSH_RELAY_URL in this run (Linux wrapper style): push never installs.
echo "$log4" | grep -q "dcolinmorgan/herdr-push" && fail "push must be skipped without a relay URL" || true
[ ! -e "$home4/.config/herdr/plugins/config/herdr.push/.env" ] \
  || fail "no push .env may be seeded without a relay URL"

# --- Case 5: existing live file is backed up before overwrite ----------------
stub5="$tmp/stub5"; make_stub "$stub5"; home5="$tmp/home5"
mkdir -p "$home5/.config/herdr"
echo 'user-edited = true' >"$home5/.config/herdr/config.toml"
# Do NOT use run_case here: it wipes the home dir, deleting the pre-existing
# live file this case is checking.
(
  export HOME="$home5"
  export STUB_LOG="$home5/calls.log"
  export HERDR_TEMPLATE="$template"
  export HERDR_CONFIG_DIR="$home5/.config/herdr"
  export HERDR_PROJECTS_BIN="$home5/nonexistent-herdr-projects"
  export STUB_MODE=ok STUB_VERSION=0.9.5
  env PATH="$stub5/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
ls "$home5/.config/herdr"/config.toml.bak-* >/dev/null 2>&1 \
  || fail "pre-existing config.toml should be backed up"

# --- Case 6: an existing herdr-push .env is never overwritten ---------------
stub6="$tmp/stub6"; make_stub "$stub6"; home6="$tmp/home6"
push_env6="$home6/.config/herdr/plugins/config/herdr.push"
mkdir -p "$push_env6"
echo 'HERDR_RELAY=https://tunnel.example.invalid' >"$push_env6/.env"
(
  export HOME="$home6"
  export STUB_LOG="$home6/calls.log"
  export HERDR_TEMPLATE="$template"
  export HERDR_CONFIG_DIR="$home6/.config/herdr"
  export HERDR_PROJECTS_BIN="$home6/nonexistent-herdr-projects"
  export HERDR_PUSH_RELAY_URL="http://127.0.0.1:8375"
  export STUB_MODE=ok STUB_VERSION=0.9.5
  env PATH="$stub6/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
grep -Fxq "HERDR_RELAY=https://tunnel.example.invalid" "$push_env6/.env" \
  || fail "user-edited herdr-push .env must be preserved, got: $(cat "$push_env6/.env")"
grep -Fq "127.0.0.1" "$push_env6/.env" \
  && fail "activation must not append the default relay URL to a seeded .env" || true

# --- Case 7: upstream 1.2.x registered -> uninstall it and kill orphans ------
# The one-time rolloff window: plugin id herdr-projects is occupied by the
# incompatible eliasstravik 1.2.x task-board plugin, and its four helper
# daemons (keeper / keeper-work / voice helper / serve) linger after
# uninstall. Activation must uninstall first, signal exactly those argv
# patterns (stubbed pkill here), and only then install the 0.2 fork.
stub7="$tmp/stub7"; make_stub "$stub7"; home7="$tmp/home7"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PROJECTS_PIN="eliasstravik/herdr-projects@v1.2.13" \
  run_case "$home7" env PATH="$stub7/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log7="$(cat "$home7/calls.log")"
uninst=$(echo "$log7" | grep -n "plugin uninstall herdr-projects" | head -1 | cut -d: -f1)
kill_line=$(echo "$log7" | grep -n "pkill" | head -1 | cut -d: -f1)
proj_inst7=$(echo "$log7" | grep -n "plugin install -y --ref v0.2.34-pf.17" | head -1 | cut -d: -f1)
[ -n "$uninst" ] || fail "upstream 1.2 plugin must be uninstalled before the fork installs"
[ -n "$kill_line" ] || fail "orphan 1.2 daemons must be signalled after uninstall"
[ -n "$proj_inst7" ] || fail "0.2 fork must be installed in the same activation"
[ "$uninst" -lt "$kill_line" ] && [ "$kill_line" -lt "$proj_inst7" ] \
  || fail "order must be: uninstall ($uninst) -> pkill ($kill_line) -> fork install ($proj_inst7)"
# The kill must target the four helper roles by argv suffix, never the 0.2
# ticker (`herdr-projects --root … ticker run`, no -<os>-<arch> suffix).
# Note: the stub log encodes argv with printf %q, which backslash-escapes the
# spaces inside "voice helper".
pkill_log="$(echo "$log7" | grep 'pkill' | head -1)"
echo "$pkill_log" | grep -q -- '-f' || fail "orphan kill must use pkill -f (argv match)"
for role in keeper keeper-work voice serve; do
  echo "$pkill_log" | grep -q "$role" || fail "pkill pattern must cover role: $role"
done
echo "$pkill_log" | grep -q 'a-z0-9' || fail "pkill pattern must pin the herdr-projects-<os>-<arch> argv"
echo "$pkill_log" | grep -q 'ticker' \
  && fail "pkill pattern must never match the 0.2 ticker run" || true

# --- Case 8: 0.2 fork already pinned -> no uninstall, no pkill, no reinstall -
stub8="$tmp/stub8"; make_stub "$stub8"; home8="$tmp/home8"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PROJECTS_PIN="PannenetsF/herdr-projects@v0.2.34-pf.17" \
  run_case "$home8" env PATH="$stub8/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log8="$(cat "$home8/calls.log")"
echo "$log8" | grep -q "plugin uninstall" \
  && fail "must not uninstall when the pinned fork is already registered" || true
echo "$log8" | grep -q "pkill" \
  && fail "must not signal daemons when the pinned fork is already registered" || true
echo "$log8" | grep -q "plugin install -y --ref v0.2.34-pf.17" \
  && fail "fork must not be reinstalled when already at the pinned ref" || true
echo "$log8" | grep -q "action invoke configure --plugin herdr-projects" \
  || fail "configure must still run (idempotent repair) when the fork is present"

# --- Case 8b: previous fork pin -> upgrade only, without upstream rolloff ---
stub8b="$tmp/stub8b"; make_stub "$stub8b"; home8b="$tmp/home8b"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PROJECTS_PIN="PannenetsF/herdr-projects@v0.2.34-pf.16" \
  run_case "$home8b" env PATH="$stub8b/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log8b="$(cat "$home8b/calls.log")"
[ "$(echo "$log8b" | grep -c 'plugin install -y --ref v0.2.34-pf.17 PannenetsF/herdr-projects')" -eq 1 ] \
  || fail "previous fork pin must upgrade to pf.17 exactly once"
echo "$log8b" | grep -q "plugin uninstall" \
  && fail "fork upgrade must not uninstall the current plugin" || true
echo "$log8b" | grep -q "pkill" \
  && fail "fork upgrade must not signal daemons" || true
echo "$log8b" | grep -q "action invoke configure --plugin herdr-projects" \
  || fail "fork upgrade must retain the configure fallback"

# --- Case 9: agent integrations self-gate and are skipped when not requested -
# 9a: the installer exits 1 when an agent is not installed (real "install
# codex first" behavior); a missing agent must not abort the activation.
stub9="$tmp/stub9"; make_stub "$stub9"; home9="$tmp/home9"
STUB_MODE=ok STUB_VERSION=0.9.5 STUB_INTEGRATION_FAIL=1 \
  run_case "$home9" env PATH="$stub9/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log9="$(cat "$home9/calls.log")"
echo "$log9" | grep -q "integration install claude" || fail "integration still attempted"
echo "$log9" | grep -q "furkankly/zoetrope/herdr-plugin" \
  || fail "activation must continue after an integration self-gate"

# 9b: no HERDR_AGENT_INTEGRATIONS (e.g. a wrapper that opts out) -> no
# integration calls at all.
home9b="$tmp/home9b"; mkdir -p "$home9b"
(
  export HOME="$home9b"
  export STUB_LOG="$home9b/calls.log"
  export HERDR_TEMPLATE="$template"
  export HERDR_CONFIG_DIR="$home9b/.config/herdr"
  export HERDR_PROJECTS_BIN="$home9b/nonexistent-herdr-projects"
  export STUB_MODE=ok STUB_VERSION=0.9.5
  env PATH="$stub9/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
grep -q "integration install" "$home9b/calls.log" \
  && fail "no integration may be ensured without HERDR_AGENT_INTEGRATIONS" || true

# --- Cases 10-17: herdr-projects command relink before configure -------------
# The plugin relinks ~/.local/bin/herdr-projects only at startup / doctor
# --fix, so after a pf.N -> pf.N+1 reinstall activation must point the link at
# the checkout `herdr plugin list --json` names BEFORE running configure, and
# configure has to execute that exact binary rather than whatever the old link
# named. Fake builds log their own path on every invocation so the binary that
# ran configure is observable.
make_projects_build() {
  local home="$1" rel="$2" marker="$3"
  local dir="$home/.config/herdr/$rel/target/release"
  mkdir -p "$dir"
  cat >"$dir/herdr-projects" <<SH
#!/usr/bin/env bash
printf '%s %s\n' '$marker' "\$*" >>"\$HOME/hp-binary.log"
exit 0
SH
  chmod +x "$dir/herdr-projects"
  printf '%s\n' "$dir/herdr-projects"
}

run_relink_case() {
  local home="$1"; shift
  mkdir -p "$home"
  (
    export HOME="$home"
    export STUB_LOG="$home/calls.log"
    export HERDR_TEMPLATE="$template"
    export HERDR_CONFIG_DIR="$home/.config/herdr"
    export HERDR_PROJECTS_BIN="$home/.local/bin/herdr-projects"
    export HERDR_AGENT_INTEGRATIONS="claude codex"
    export STUB_MODE=ok STUB_VERSION=0.9.5
    "$@" 2>"$home/stderr.log"
  )
}

# Case 10: upgrade pf.N -> pf.N+1. The old link names the previous generation
# (still present on disk, as in the real pf.13 -> pf.14 incident); the JSON
# names the new checkout. The link must be swapped and configure must run on
# the NEW binary, never the old one and never via the action API fallback.
stub10="$tmp/stub10"; make_stub "$stub10"; home10="$tmp/home10"
old10="$(make_projects_build "$home10" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/11111-0/checkout" OLD)"
new10="$(make_projects_build "$home10" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/22222-0/checkout" NEW)"
mkdir -p "$home10/.local/bin"
ln -s "$old10" "$home10/.local/bin/herdr-projects"
run_relink_case "$home10" env PATH="$stub10/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$home10/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/22222-0/checkout" \
  bash "$repo_root/install-herdr-plugins.sh"
[ -L "$home10/.local/bin/herdr-projects" ] || fail "10: link must be a symlink"
[ "$(readlink "$home10/.local/bin/herdr-projects")" = "$new10" ] \
  || fail "10: link should target the new checkout, got $(readlink "$home10/.local/bin/herdr-projects")"
grep -q '^NEW configure$' "$home10/hp-binary.log" \
  || fail "10: configure must run on the new binary; log: $(cat "$home10/hp-binary.log" 2>/dev/null)"
grep -q '^OLD ' "$home10/hp-binary.log" \
  && fail "10: the old generation binary must never be invoked" || true
grep -q "action invoke configure --plugin herdr-projects" "$home10/calls.log" \
  && fail "10: action API fallback must not be used with a locatable new binary" || true
grep -q "relinking" "$home10/stderr.log" \
  || fail "10: a relink diagnostic must be emitted on upgrade"

# Case 11: idempotent when the link already names the active checkout — the
# link is untouched and configure still runs on that binary.
stub11="$tmp/stub11"; make_stub "$stub11"; home11="$tmp/home11"
bin11="$(make_projects_build "$home11" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/11595-0/checkout" CUR)"
mkdir -p "$home11/.local/bin"
ln -s "$bin11" "$home11/.local/bin/herdr-projects"
run_relink_case "$home11" env PATH="$stub11/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$home11/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/11595-0/checkout" \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home11/.local/bin/herdr-projects")" = "$bin11" ] \
  || fail "11: current link must be left untouched"
grep -q '^CUR configure$' "$home11/hp-binary.log" \
  || fail "11: configure must run on the current binary"
grep -q "relinking" "$home11/stderr.log" \
  && fail "11: no relink diagnostic expected when already current" || true

# Case 12: the active checkout has no built binary (build failed). Nothing may
# be linked or replaced, and configure goes through the action API, which
# dispatches server-side to whatever the server actually has enabled.
stub12="$tmp/stub12"; make_stub "$stub12"; home12="$tmp/home12"
root12="$home12/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/33333-0/checkout"
mkdir -p "$root12"
old12="$(make_projects_build "$home12" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/44444-0/checkout" OLD12)"
mkdir -p "$home12/.local/bin"
ln -s "$old12" "$home12/.local/bin/herdr-projects"
run_relink_case "$home12" env PATH="$stub12/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$root12" \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home12/.local/bin/herdr-projects")" = "$old12" ] \
  || fail "12: existing link must be preserved when the active binary is missing"
[ ! -e "$home12/hp-binary.log" ] || fail "12: no plugin binary may be invoked"
grep -q "active plugin binary not found" "$home12/stderr.log" \
  || fail "12: missing-binary diagnostic expected"
grep -q "action invoke configure --plugin herdr-projects" "$home12/calls.log" \
  || fail "12: configure must fall back to the action API"

# Case 13: a regular file at the link path is never overwritten; configure
# still runs on the located active binary via its absolute path.
stub13="$tmp/stub13"; make_stub "$stub13"; home13="$tmp/home13"
make_projects_build "$home13" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/55555-0/checkout" F13 >/dev/null
mkdir -p "$home13/.local/bin"
printf 'hand-managed\n' >"$home13/.local/bin/herdr-projects"
run_relink_case "$home13" env PATH="$stub13/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$home13/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/55555-0/checkout" \
  bash "$repo_root/install-herdr-plugins.sh"
[ -f "$home13/.local/bin/herdr-projects" ] && [ ! -L "$home13/.local/bin/herdr-projects" ] \
  || fail "13: regular file must not be replaced by a symlink"
grep -Fxq "hand-managed" "$home13/.local/bin/herdr-projects" \
  || fail "13: regular file contents must be preserved"
grep -q '^F13 configure$' "$home13/hp-binary.log" \
  || fail "13: configure must run on the active binary despite the file"
grep -q "action invoke configure --plugin herdr-projects" "$home13/calls.log" \
  && fail "13: action API fallback unnecessary when the binary is locatable" || true

# Case 14: a working symlink to a path OUTSIDE Herdr's plugin tree (the user's
# own checkout) is a deliberate override and must be left alone; configure
# still uses the active install's binary directly.
stub14="$tmp/stub14"; make_stub "$stub14"; home14="$tmp/home14"
make_projects_build "$home14" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/66666-0/checkout" F14 >/dev/null
own14="$home14/dev/herdr-projects/target/release/herdr-projects"
mkdir -p "$(dirname "$own14")"
printf '#!/usr/bin/env bash\nexit 0\n' >"$own14"; chmod +x "$own14"
mkdir -p "$home14/.local/bin"
ln -s "$own14" "$home14/.local/bin/herdr-projects"
run_relink_case "$home14" env PATH="$stub14/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$home14/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/66666-0/checkout" \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home14/.local/bin/herdr-projects")" = "$own14" ] \
  || fail "14: foreign link must be preserved"
grep -q '^F14 configure$' "$home14/hp-binary.log" \
  || fail "14: configure must run on the active install's binary"

# Case 15: JSON unavailable (older herdr) — the filesystem scan must resolve
# the active build from both install layouts. 15a: the existing link names one
# of several builds, so that one wins regardless of mtime. 15b: no link, the
# newest build wins. 15c: the legacy plugins/github layout is supported.
stub15="$tmp/stub15"; make_stub "$stub15"; home15="$tmp/home15a"
a15="$(make_projects_build "$home15" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/77777-0/checkout" A15)"
b15="$(make_projects_build "$home15" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/88888-0/checkout" B15)"
# A is made first; force B's mtime newer so the test does not depend on the
# sub-second creation order, then prove the existing-link preference beats it.
touch -t 202001010000 "$a15"
touch -t 202101010000 "$b15"
mkdir -p "$home15/.local/bin"
ln -s "$a15" "$home15/.local/bin/herdr-projects"
run_relink_case "$home15" env PATH="$stub15/bin:/usr/bin:/bin" STUB_NO_JSON=1 \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home15/.local/bin/herdr-projects")" = "$a15" ] \
  || fail "15a: existing link's target must be preferred over newer builds"
grep -q '^A15 configure$' "$home15/hp-binary.log" \
  || fail "15a: configure must run on the link-named binary"

home15b="$tmp/home15b"
a15b="$(make_projects_build "$home15b" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/77777-0/checkout" A15B)"
b15b="$(make_projects_build "$home15b" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/88888-0/checkout" B15B)"
touch -t 202001010000 "$a15b"
touch -t 202101010000 "$b15b"
run_relink_case "$home15b" env PATH="$stub15/bin:/usr/bin:/bin" STUB_NO_JSON=1 \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home15b/.local/bin/herdr-projects")" = "$b15b" ] \
  || fail "15b: without a link, the newest build must be chosen"
grep -q '^B15B configure$' "$home15b/hp-binary.log" \
  || fail "15b: configure must run on the newest binary"

home15c="$tmp/home15c"
legacy15="$(make_projects_build "$home15c" \
  "plugins/github/herdr-projects-b1278ffb803c" LEGACY15)"
run_relink_case "$home15c" env PATH="$stub15/bin:/usr/bin:/bin" STUB_NO_JSON=1 \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home15c/.local/bin/herdr-projects")" = "$legacy15" ] \
  || fail "15c: legacy plugins/github layout must be discovered"
grep -q '^LEGACY15 configure$' "$home15c/hp-binary.log" \
  || fail "15c: configure must run on the legacy-layout binary"

# Case 16: a JSON entry owned by eliasstravik (the rolled-off 1.2.x plugin)
# must never be linked as the fork's command; with no fork build on disk the
# activation keeps its hands off and uses the action API.
stub16="$tmp/stub16"; make_stub "$stub16"; home16="$tmp/home16"
bad16="$home16/.config/herdr/plugins/github-installations/herdr-projects-000000000000/99999-0/checkout"
make_projects_build "$home16" \
  "plugins/github-installations/herdr-projects-000000000000/99999-0/checkout" BAD16 >/dev/null
# Rename it onto the 1.2 slug so the fork-pattern globs cannot match it.
mv "$home16/.config/herdr/plugins/github-installations/herdr-projects-000000000000" \
  "$home16/.config/herdr/plugins/github-installations/evil-1-2"
run_relink_case "$home16" env PATH="$stub16/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$bad16" STUB_PROJECTS_OWNER="eliasstravik" \
  bash "$repo_root/install-herdr-plugins.sh"
[ ! -e "$home16/.local/bin/herdr-projects" ] \
  || fail "16: no link may be created for the upstream 1.2.x plugin"
[ ! -e "$home16/hp-binary.log" ] || fail "16: the 1.2.x binary must not be invoked"
grep -q "action invoke configure --plugin herdr-projects" "$home16/calls.log" \
  || fail "16: configure must fall back to the action API"

# Case 17: a dangling link (a removed previous generation) is replaced even
# though its literal target string sits outside the current plugins path.
stub17="$tmp/stub17"; make_stub "$stub17"; home17="$tmp/home17"
bin17="$(make_projects_build "$home17" \
  "plugins/github-installations/herdr-projects-b1278ffb803c/12121-0/checkout" F17)"
mkdir -p "$home17/.local/bin"
ln -s "$home17/gone-generation/target/release/herdr-projects" \
  "$home17/.local/bin/herdr-projects"
run_relink_case "$home17" env PATH="$stub17/bin:/usr/bin:/bin" \
  STUB_PROJECTS_ROOT="$home17/.config/herdr/plugins/github-installations/herdr-projects-b1278ffb803c/12121-0/checkout" \
  bash "$repo_root/install-herdr-plugins.sh"
[ "$(readlink "$home17/.local/bin/herdr-projects")" = "$bin17" ] \
  || fail "17: dangling link must be replaced by the active binary"
grep -q '^F17 configure$' "$home17/hp-binary.log" \
  || fail "17: configure must run on the active binary"

# --- Case 18: migrate legacy web-ui + local ovis + local roadboard -----------
# Simulates a machine transitioning from legacy devswha.herdr-web-ui and local
# plugin links for devswha.ovis and roadboard to the pinned remote GitHub forks.
stub18="$tmp/stub18"; make_stub "$stub18"; home18="$tmp/home18"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST=$'- devswha.herdr-web-ui (herdr web ui) enabled [github:devswha/herdr-web-ui@v0.4.11]\n- devswha.ovis (Ovis) enabled [local:/Users/test/Documents/ovis]\n- roadboard (Roadboard) enabled [local:/Users/test/Documents/workspace/roadboard]' \
  run_case "$home18" env PATH="$stub18/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log18="$(cat "$home18/calls.log")"

# Legacy web-ui must be stopped and uninstalled (no -y flag) before ovis installs.
webui_stop=$(echo "$log18" | grep -n "plugin action invoke stop --plugin devswha.herdr-web-ui" | head -1 | cut -d: -f1)
webui_uninst=$(echo "$log18" | grep -n "plugin uninstall devswha.herdr-web-ui" | head -1 | cut -d: -f1)
ovis_unlink=$(echo "$log18" | grep -n "plugin unlink devswha.ovis" | head -1 | cut -d: -f1)
ovis_inst=$(echo "$log18" | grep -n "OVIS_FROM_SOURCE=1 plugin install -y --ref pf/0.5.11-1 PannenetsF/ovis" | head -1 | cut -d: -f1)
ovis_stop=$(echo "$log18" | grep -n "plugin action invoke stop --plugin devswha.ovis" | head -1 | cut -d: -f1)
ovis_start=$(echo "$log18" | grep -n "plugin action invoke start --plugin devswha.ovis" | head -1 | cut -d: -f1)
[ -n "$webui_stop" ] || fail "18: legacy devswha.herdr-web-ui must be stopped"
[ -n "$webui_uninst" ] || fail "18: legacy devswha.herdr-web-ui must be uninstalled"
echo "$log18" | grep -q "plugin uninstall -y" \
  && fail "18: herdr plugin uninstall must not be passed -y" || true
[ -n "$ovis_unlink" ] || fail "18: local devswha.ovis link must be unlinked"
[ -n "$ovis_inst" ] || fail "18: pinned remote PannenetsF/ovis must be installed"
[ -n "$ovis_stop" ] || fail "18: devswha.ovis must be stopped after install so start replaces the old local bridge"
[ -n "$ovis_start" ] || fail "18: devswha.ovis start action must run"
[ "$webui_stop" -lt "$webui_uninst" ] && [ "$webui_uninst" -lt "$ovis_unlink" ] \
  && [ "$ovis_unlink" -lt "$ovis_inst" ] && [ "$ovis_inst" -lt "$ovis_stop" ] \
  && [ "$ovis_stop" -lt "$ovis_start" ] \
  || fail "18: ovis migration order wrong ($webui_stop -> $webui_uninst -> $ovis_unlink -> $ovis_inst -> $ovis_stop -> $ovis_start)"

# Local roadboard link must be unlinked before remote install.
rb_unlink=$(echo "$log18" | grep -n "plugin unlink roadboard" | head -1 | cut -d: -f1)
rb_inst=$(echo "$log18" | grep -n "plugin install -y --ref v0.1.0-pf.1 PannenetsF/roadboard" | head -1 | cut -d: -f1)
[ -n "$rb_unlink" ] || fail "18: local roadboard link must be unlinked"
[ -n "$rb_inst" ] || fail "18: pinned remote PannenetsF/roadboard must be installed"
[ "$rb_unlink" -lt "$rb_inst" ] \
  || fail "18: roadboard unlink ($rb_unlink) must precede remote install ($rb_inst)"

# --- Case 19: idempotent re-run when pinned remote ovis + roadboard present --
stub19="$tmp/stub19"; make_stub "$stub19"; home19="$tmp/home19"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST=$'- devswha.ovis (Ovis) enabled [github:PannenetsF/ovis@pf/0.5.11-1]\n- roadboard (Roadboard) enabled [github:PannenetsF/roadboard@v0.1.0-pf.1]' \
  run_case "$home19" env PATH="$stub19/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log19="$(cat "$home19/calls.log")"

echo "$log19" | grep -q "plugin uninstall devswha.herdr-web-ui" \
  && fail "19: must not uninstall legacy web-ui when absent" || true
echo "$log19" | grep -q "plugin unlink devswha.ovis" \
  && fail "19: must not unlink pinned remote ovis" || true
echo "$log19" | grep -q "PannenetsF/ovis" \
  && fail "19: must not reinstall ovis when already at pinned ref" || true
echo "$log19" | grep -q "plugin action invoke stop --plugin devswha.ovis" \
  && fail "19: must not stop ovis on an idempotent activation" || true
echo "$log19" | grep -q "plugin action invoke start --plugin devswha.ovis" \
  || fail "19: ovis start action must still run on idempotent activation"
echo "$log19" | grep -q "plugin unlink roadboard" \
  && fail "19: must not unlink pinned remote roadboard" || true
echo "$log19" | grep -q "PannenetsF/roadboard" \
  && fail "19: must not reinstall roadboard when already at pinned ref" || true

# --- Case 20: different / prefix-colliding GitHub refs upgrade in place ------
# Anchoring with closing `]` ensures pf/0.5.11-10 does not match pf/0.5.11-1 and
# v0.1.0-pf.10 does not match v0.1.0-pf.1. GitHub plugins upgrade in place
# without `plugin unlink`, and Ovis restarts onto the new checkout after install.
stub20="$tmp/stub20"; make_stub "$stub20"; home20="$tmp/home20"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST=$'- devswha.ovis (Ovis) enabled [github:PannenetsF/ovis@pf/0.5.11-10]\n- roadboard (Roadboard) enabled [github:PannenetsF/roadboard@v0.1.0-pf.10]' \
  run_case "$home20" env PATH="$stub20/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log20="$(cat "$home20/calls.log")"

echo "$log20" | grep -q "plugin unlink devswha.ovis" \
  && fail "20: must not unlink remote github ovis on ref upgrade" || true
echo "$log20" | grep -q "plugin unlink roadboard" \
  && fail "20: must not unlink remote github roadboard on ref upgrade" || true
ovis20_inst=$(echo "$log20" | grep -n "OVIS_FROM_SOURCE=1 plugin install -y --ref pf/0.5.11-1 PannenetsF/ovis" | head -1 | cut -d: -f1)
ovis20_stop=$(echo "$log20" | grep -n "plugin action invoke stop --plugin devswha.ovis" | head -1 | cut -d: -f1)
ovis20_start=$(echo "$log20" | grep -n "plugin action invoke start --plugin devswha.ovis" | head -1 | cut -d: -f1)
[ -n "$ovis20_inst" ] || fail "20: prefix-colliding ovis ref must still trigger install"
[ -n "$ovis20_stop" ] || fail "20: ovis must be stopped after ref upgrade install"
[ -n "$ovis20_start" ] || fail "20: ovis must be started after ref upgrade install"
[ "$ovis20_inst" -lt "$ovis20_stop" ] && [ "$ovis20_stop" -lt "$ovis20_start" ] \
  || fail "20: ovis upgrade order wrong ($ovis20_inst -> $ovis20_stop -> $ovis20_start)"
echo "$log20" | grep -q "plugin install -y --ref v0.1.0-pf.1 PannenetsF/roadboard" \
  || fail "20: prefix-colliding roadboard ref must still trigger install"

# --- Case 21: failed ovis install must not stop an existing running bridge ---
stub21="$tmp/stub21"; make_stub "$stub21"; home21="$tmp/home21"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST=$'- devswha.ovis (Ovis) enabled [github:PannenetsF/ovis@pf/0.5.9-1]' \
  STUB_FAIL_INSTALL_REPO="PannenetsF/ovis" \
  run_case "$home21" env PATH="$stub21/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log21="$(cat "$home21/calls.log")"

echo "$log21" | grep -q "OVIS_FROM_SOURCE=1 plugin install -y --ref pf/0.5.11-1 PannenetsF/ovis" \
  || fail "21: ovis install must be attempted"
echo "$log21" | grep -q "plugin action invoke stop --plugin devswha.ovis" \
  && fail "21: failed ovis install must not stop the existing bridge" || true
echo "$log21" | grep -q "plugin action invoke start --plugin devswha.ovis" \
  || fail "21: ovis start action must still run"

# --- Case 22: roadboard command link migration & daemon restart --------------
# Migrating from [local:<checkout>] updates ~/.local/bin/roadboard pointing into
# that old local checkout to the active GitHub-installed binary and restarts the
# daemon (`daemon stop` then `daemon kick`). An idempotent run does not stop
# the daemon, and an unrelated foreign symlink is left untouched.
stub22a="$tmp/stub22a"; make_stub "$stub22a"; home22a="$tmp/home22a"
rb_old_local="$tmp/old-local-roadboard-22"
rb_remote_root="$tmp/remote-roadboard-22"
rb_link22="$tmp/rb-link-22"
mkdir -p "$rb_old_local/target/release" "$rb_remote_root/target/release"
cat >"$rb_old_local/target/release/roadboard" <<'SH'
#!/usr/bin/env bash
printf 'old-roadboard %s\n' "$*" >>"$STUB_LOG"
SH
cat >"$rb_remote_root/target/release/roadboard" <<'SH'
#!/usr/bin/env bash
printf 'remote-roadboard %s\n' "$*" >>"$STUB_LOG"
SH
chmod +x "$rb_old_local/target/release/roadboard" "$rb_remote_root/target/release/roadboard"
ln -s "$rb_old_local/target/release/roadboard" "$rb_link22"

STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST="- roadboard (Roadboard) enabled [local:$rb_old_local]" \
  STUB_ROADBOARD_ROOT="$rb_remote_root" \
  run_case "$home22a" env HERDR_ROADBOARD_BIN="$rb_link22" \
  PATH="$stub22a/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log22a="$(cat "$home22a/calls.log")"

[ "$(readlink "$rb_link22")" = "$rb_remote_root/target/release/roadboard" ] \
  || fail "22a: migrated local roadboard link must point to active remote binary (got $(readlink "$rb_link22"))"
rb22_stop=$(echo "$log22a" | grep -n "remote-roadboard daemon stop" | head -1 | cut -d: -f1)
rb22_kick=$(echo "$log22a" | grep -n "remote-roadboard daemon kick" | head -1 | cut -d: -f1)
[ -n "$rb22_stop" ] && [ -n "$rb22_kick" ] && [ "$rb22_stop" -lt "$rb22_kick" ] \
  || fail "22a: roadboard daemon must stop then kick after install ($rb22_stop -> $rb22_kick)"

# Idempotent run: no stop, only kick; foreign link is preserved.
rb_foreign="$tmp/foreign-roadboard-22"
printf '#!/usr/bin/env bash\nexit 0\n' >"$rb_foreign"
chmod +x "$rb_foreign"
ln -sfn "$rb_foreign" "$rb_link22"
home22b="$tmp/home22b"
STUB_MODE=ok STUB_VERSION=0.9.5 \
  STUB_PLUGIN_LIST="- roadboard (Roadboard) enabled [github:PannenetsF/roadboard@v0.1.0-pf.1]" \
  STUB_ROADBOARD_ROOT="$rb_remote_root" \
  run_case "$home22b" env HERDR_ROADBOARD_BIN="$rb_link22" \
  PATH="$stub22a/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log22b="$(cat "$home22b/calls.log")"

[ "$(readlink "$rb_link22")" = "$rb_foreign" ] \
  || fail "22b: unrelated foreign roadboard symlink must be left untouched"
echo "$log22b" | grep -q "remote-roadboard daemon stop" \
  && fail "22b: idempotent run must not stop roadboard daemon" || true
echo "$log22b" | grep -q "remote-roadboard daemon kick" \
  || fail "22b: idempotent run should still kick roadboard daemon"

echo "all herdr plugin activation cases passed"