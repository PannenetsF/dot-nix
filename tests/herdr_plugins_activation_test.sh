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
      list) echo '[]' ;;
      config-dir)
        # Real herdr prints the plugin's config dir and creates it on demand.
        d="$HOME/.config/herdr/plugins/config/$3"
        mkdir -p "$d"
        printf '%s\n' "$d"
        ;;
    esac
    ;;
esac
exit 0
SH
  chmod +x "$dir/bin/herdr"
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
    export HERDR_ROADBOARD_SRC="$home/no-roadboard"
    "$@"
  )
}

# --- Case 1: fresh machine, server 0.9.4 -> template + every pinned plugin --
stub1="$tmp/stub1"; make_stub "$stub1"; home1="$tmp/home1"
STUB_MODE=ok STUB_VERSION=0.9.4 \
  HERDR_PUSH_RELAY_URL=http://127.0.0.1:8375 \
  run_case "$home1" env PATH="$stub1/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"

[ -f "$home1/.config/herdr/config.toml" ] || fail "template not installed"
grep -q "marker = 1" "$home1/.config/herdr/config.toml" || fail "template content wrong"
[ ! -L "$home1/.config/herdr/config.toml" ] || fail "config must be a regular file, not symlink"

log1="$(cat "$home1/calls.log")"
echo "$log1" | grep -q "furkankly/zoetrope/herdr-plugin" || fail "zoetrope not installed"
echo "$log1" | grep -q "PannenetsF/herdr-radar" || fail "radar not installed"
echo "$log1" | grep -q "eliasstravik/herdr-projects" || fail "projects not installed"
echo "$log1" | grep -q "plugin install -y --ref v1.2.13 eliasstravik/herdr-projects" \
  || fail "projects not installed at the pinned upstream ref"
echo "$log1" | grep -q "server reload-config" || fail "server config not reloaded"

# radar configure repairs its marker blocks after the template reinstall;
# herdr-projects 1.2 writes no config blocks, so no relative order is required
# between the two anymore.
echo "$log1" | grep -q "action invoke configure" || fail "radar configure action missing"
proj_inst=$(echo "$log1" | grep -n "plugin install -y --ref v1.2.13" | head -1 | cut -d: -f1)
[ -n "$proj_inst" ] || fail "projects install not found in log"

# state-start is invoked so the glyph daemon comes up without a server restart.
echo "$log1" | grep -q "action invoke state-start" || fail "radar state-start missing"

# web-ui: pinned install + immediate bridge start (startup hooks only fire on
# server start).
echo "$log1" | grep -q "plugin install -y --ref v0.4.11 devswha/herdr-web-ui" \
  || fail "web-ui not installed at the pinned ref"
echo "$log1" | grep -q "action invoke start --plugin devswha.herdr-web-ui" \
  || fail "web-ui start action missing"

# herdr-portal: fork pin v1.3.0-pf.1 (on upstream's untagged 1.3.0 release
# commit) which keeps agent_status=unknown panes on the board by routing
# them into the working column. Installed on every platform; it opens on
# demand, so no action is invoked by activation.
echo "$log1" | grep -q "plugin install -y --ref v1.3.0-pf.1 PannenetsF/herdr-portal" \
  || fail "herdr-portal not installed at the pinned fork ref"
echo "$log1" | grep -q "herdr-portal.open" \
  && fail "portal opens on user request only; activation must not invoke it" || true

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
echo "$log3" | grep -q "PannenetsF/herdr-radar" && fail "radar needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "eliasstravik/herdr-projects" && fail "projects needs a reachable >=0.9.3 server" || true
echo "$log3" | grep -q "devswha/herdr-web-ui" && fail "web-ui needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "PannenetsF/herdr-portal" && fail "portal installs inside the version gate" || true
echo "$log3" | grep -q "dcolinmorgan/herdr-push" && fail "push must wait for a reachable server" || true
[ ! -e "$home3/.config/herdr/plugins/config/herdr.push/.env" ] \
  || fail "push .env must not be seeded when the plugin did not install"
echo "$log3" | grep -q "server reload-config" || fail "reload-config should still run"

# --- Case 4: server 0.9.2 -> radar/web-ui allowed, projects gated out ---------
stub4="$tmp/stub4"; make_stub "$stub4"; home4="$tmp/home4"
STUB_MODE=ok STUB_VERSION=0.9.2 \
  run_case "$home4" env PATH="$stub4/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log4="$(cat "$home4/calls.log")"
echo "$log4" | grep -q "PannenetsF/herdr-radar" || fail "radar allowed on 0.9.2"
echo "$log4" | grep -q "eliasstravik/herdr-projects" && fail "projects needs >= 0.9.3" || true
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
  export HERDR_ROADBOARD_SRC="$home5/no-roadboard"
  export STUB_MODE=ok STUB_VERSION=0.9.4
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
  export HERDR_ROADBOARD_SRC="$home6/no-roadboard"
  export HERDR_PUSH_RELAY_URL="http://127.0.0.1:8375"
  export STUB_MODE=ok STUB_VERSION=0.9.4
  env PATH="$stub6/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
grep -Fxq "HERDR_RELAY=https://tunnel.example.invalid" "$push_env6/.env" \
  || fail "user-edited herdr-push .env must be preserved, got: $(cat "$push_env6/.env")"
grep -Fq "127.0.0.1" "$push_env6/.env" \
  && fail "activation must not append the default relay URL to a seeded .env" || true

# --- Case 7: server exactly 0.9.3 -> projects allowed at the boundary --------
stub7="$tmp/stub7"; make_stub "$stub7"; home7="$tmp/home7"
STUB_MODE=ok STUB_VERSION=0.9.3 \
  run_case "$home7" env PATH="$stub7/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log7="$(cat "$home7/calls.log")"
echo "$log7" | grep -q "plugin install -y --ref v1.2.13 eliasstravik/herdr-projects" \
  || fail "projects must install on a server that is exactly 0.9.3"

echo "all herdr plugin activation cases passed"
