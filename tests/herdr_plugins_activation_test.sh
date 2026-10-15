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
    # Always report an empty plugin set so install guards see "missing".
    [ "$2" = list ] && echo '[]'
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
    export HERDR_PROJECTS_BIN="$home/nonexistent-herdr-projects"
    export HERDR_ROADBOARD_SRC="$home/no-roadboard"
    "$@"
  )
}

# --- Case 1: fresh machine, server 0.9.4 -> template + every pinned plugin --
stub1="$tmp/stub1"; make_stub "$stub1"; home1="$tmp/home1"
STUB_MODE=ok STUB_VERSION=0.9.4 \
  run_case "$home1" env PATH="$stub1/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"

[ -f "$home1/.config/herdr/config.toml" ] || fail "template not installed"
grep -q "marker = 1" "$home1/.config/herdr/config.toml" || fail "template content wrong"
[ ! -L "$home1/.config/herdr/config.toml" ] || fail "config must be a regular file, not symlink"

log1="$(cat "$home1/calls.log")"
echo "$log1" | grep -q "furkankly.zoetrope/herdr-plugin" || fail "zoetrope not installed"
echo "$log1" | grep -q "PannenetsF/herdr-radar" || fail "radar not installed"
echo "$log1" | grep -q "PannenetsF/herdr-projects" || fail "projects not installed"
echo "$log1" | grep -q "server reload-config" || fail "server config not reloaded"

# radar configure must precede projects install (marker-block ownership order).
radar_cfg=$(echo "$log1" | grep -n "action invoke configure" | head -1 | cut -d: -f1)
proj_inst=$(echo "$log1" | grep -n "plugin install -y --ref v0.2.34-pf.1" | head -1 | cut -d: -f1)
[ -n "$radar_cfg" ] && [ -n "$proj_inst" ] && [ "$radar_cfg" -lt "$proj_inst" ] \
  || fail "radar configure ($radar_cfg) must run before projects install ($proj_inst)"

# state-start is invoked so the glyph daemon comes up without a server restart.
echo "$log1" | grep -q "action invoke state-start" || fail "radar state-start missing"

# --- Case 2: no herdr binary -> template lands, plugins skipped, exit 0 -----
home2="$tmp/home2"; mkdir -p "$home2"
run_case "$home2" env PATH="/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
[ -f "$home2/.config/herdr/config.toml" ] || fail "template should land without herdr"
[ ! -e "$home2/calls.log" ] || fail "no herdr calls expected when binary absent"

# --- Case 3: server down (bad status payload) -> plugins skipped ------------
stub3="$tmp/stub3"; make_stub "$stub3"; home3="$tmp/home3"
STUB_MODE=down run_case "$home3" env PATH="$stub3/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log3="$(cat "$home3/calls.log")"
# zoetrope installs before the status gate (unchanged from the original
# activation); the gated radar/projects set must not install while the
# server version is unobtainable.
echo "$log3" | grep -q "furkankly.zoetrope/herdr-plugin" || fail "zoetrope installs before the version gate"
echo "$log3" | grep -q "PannenetsF/herdr-radar" && fail "radar needs a reachable >=0.9.0 server" || true
echo "$log3" | grep -q "PannenetsF/herdr-projects" && fail "projects needs a reachable >=0.9.1 server" || true
echo "$log3" | grep -q "server reload-config" || fail "reload-config should still run"

# --- Case 4: server 0.9.0 -> radar allowed, projects gated out ---------------
stub4="$tmp/stub4"; make_stub "$stub4"; home4="$tmp/home4"
STUB_MODE=ok STUB_VERSION=0.9.0 \
  run_case "$home4" env PATH="$stub4/bin:/usr/bin:/bin" \
  bash "$repo_root/install-herdr-plugins.sh"
log4="$(cat "$home4/calls.log")"
echo "$log4" | grep -q "PannenetsF/herdr-radar" || fail "radar allowed on 0.9.0"
echo "$log4" | grep -q "PannenetsF/herdr-projects" && fail "projects needs >= 0.9.1" || true

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
  export STUB_MODE=ok STUB_VERSION=0.9.4
  env PATH="$stub5/bin:/usr/bin:/bin" bash "$repo_root/install-herdr-plugins.sh"
)
ls "$home5/.config/herdr"/config.toml.bak-* >/dev/null 2>&1 \
  || fail "pre-existing config.toml should be backed up"

echo "all herdr plugin activation cases passed"
