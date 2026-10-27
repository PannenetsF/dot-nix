#!/usr/bin/env bash
# Behavior tests for install-herdr-plugins.sh: the shared herdr post-activation
# body used by nix-darwin (macOS) and Home Manager (Linux). A stub `herdr`
# records its argv; nothing here touches the real config or server.
set -euo pipefail

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
        # STUB_PROJECTS_PIN simulates an already-registered projects plugin,
        # e.g. eliasstravik/herdr-projects@v1.2.13 for the rolloff case.
        if [ -n "${STUB_PROJECTS_PIN:-}" ]; then
          printf -- '- herdr-projects (Projects) enabled [github:%s]\n' "$STUB_PROJECTS_PIN"
        else
          echo '[]'
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
    export HERDR_ROADBOARD_SRC="$home/no-roadboard"
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
echo "$log1" | grep -q "plugin install -y --ref v1.4.9-pf.2 PannenetsF/herdr-radar" \
  || fail "radar not installed at the pinned fork ref"
echo "$log1" | grep -q "PannenetsF/herdr-projects" || fail "projects not installed"
echo "$log1" | grep -q "server reload-config" || fail "server config not reloaded"

# radar configure must precede projects install (marker-block ownership order).
radar_cfg=$(echo "$log1" | grep -n "action invoke configure" | head -1 | cut -d: -f1)
proj_inst=$(echo "$log1" | grep -n "plugin install -y --ref v0.2.34-pf.5" | head -1 | cut -d: -f1)
[ -n "$radar_cfg" ] && [ -n "$proj_inst" ] && [ "$radar_cfg" -lt "$proj_inst" ] \
  || fail "radar configure ($radar_cfg) must run before projects install ($proj_inst)"

# state-start is invoked so the glyph daemon comes up without a server restart.
echo "$log1" | grep -q "action invoke state-start" || fail "radar state-start missing"

# web-ui: pinned install + immediate bridge start (startup hooks only fire on
# server start).
echo "$log1" | grep -q "plugin install -y --ref v0.4.11 devswha/herdr-web-ui" \
  || fail "web-ui not installed at the pinned ref"
echo "$log1" | grep -q "action invoke start --plugin devswha.herdr-web-ui" \
  || fail "web-ui start action missing"

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
run_case "$home2" env PATH="/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
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
echo "$log3" | grep -q "devswha/herdr-web-ui" && fail "web-ui needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "PannenetsF/herdr-portal" && fail "portal installs inside the version gate" || true
echo "$log3" | grep -q "dcolinmorgan/herdr-push" && fail "push must wait for a reachable server" || true
[ ! -e "$home3/.config/herdr/plugins/config/herdr.push/.env" ] \
  || fail "push .env must not be seeded when the plugin did not install"
echo "$log3" | grep -q "server reload-config" || fail "reload-config should still run"

# --- Case 4: server 0.9.0 -> radar allowed, projects gated out ---------------
stub4="$tmp/stub4"; make_stub "$stub4"; home4="$tmp/home4"
STUB_MODE=ok STUB_VERSION=0.9.0 \
  run_case "$home4" env PATH="$stub4/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log4="$(cat "$home4/calls.log")"
echo "$log4" | grep -q "PannenetsF/herdr-radar" || fail "radar allowed on 0.9.0"
echo "$log4" | grep -q "PannenetsF/herdr-projects" && fail "projects needs >= 0.9.5" || true
echo "$log4" | grep -q "devswha/herdr-web-ui" || fail "web-ui allowed on 0.9.0 (min_herdr_version)"
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
  export HERDR_ROADBOARD_SRC="$home5/no-roadboard"
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
  export HERDR_ROADBOARD_SRC="$home6/no-roadboard"
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
proj_inst7=$(echo "$log7" | grep -n "plugin install -y --ref v0.2.34-pf.5" | head -1 | cut -d: -f1)
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
  STUB_PROJECTS_PIN="PannenetsF/herdr-projects@v0.2.34-pf.5" \
  run_case "$home8" env PATH="$stub8/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log8="$(cat "$home8/calls.log")"
echo "$log8" | grep -q "plugin uninstall" \
  && fail "must not uninstall when the pinned fork is already registered" || true
echo "$log8" | grep -q "pkill" \
  && fail "must not signal daemons when the pinned fork is already registered" || true
echo "$log8" | grep -q "plugin install -y --ref v0.2.34-pf.5" \
  && fail "fork must not be reinstalled when already at the pinned ref" || true
echo "$log8" | grep -q "action invoke configure --plugin herdr-projects" \
  || fail "configure must still run (idempotent repair) when the fork is present"

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
  export HERDR_ROADBOARD_SRC="$home9b/no-roadboard"
  export STUB_MODE=ok STUB_VERSION=0.9.5
  env PATH="$stub9/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
grep -q "integration install" "$home9b/calls.log" \
  && fail "no integration may be ensured without HERDR_AGENT_INTEGRATIONS" || true

echo "all herdr plugin activation cases passed"