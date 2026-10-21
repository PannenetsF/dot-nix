#!/usr/bin/env bash
# Shared preamble for the five herdr popup launchers (new-project, pick-project,
# add-repo, new-coordinator, focus-coordinator). Each script sources the
# sibling copy of this file next to it (see the inline resolution block in each
# launcher); it must not be relied on to live anywhere on PATH. It deliberately
# does NOT enable `set -euo pipefail` itself: the sourcing script owns its own
# options, and this file must behave identically whether or not the caller set
# them.
#
# These launchers speak herdr-projects 1.2.x's model: the board's unit of work
# is a TASK (repo/123); git repos register themselves in data/repos.json on
# first use, and each repo can have one pump-managed project coordinator
# (agent name sw-coordinator-<repo>) whose state lives in
# data/coordinator/<session>/projects/<repo>/state.json. There is no project
# slug and no `configure` step anymore.
#
# Bash 3.2-safe (macOS ships 3.2): no readarray/mapfile, no readlink -f/realpath.

# Popups close the moment the launcher script exits, so a bare error would
# flash by.
die() {
  printf '\nERROR: %s\n' "$1" >&2
  printf 'press enter to close' >&2
  read -r _ || true
  exit 1
}

# herdr runs popups with a bare launchd PATH: fzf lives in the nix profile
# (/etc/profiles/per-user/<user>/bin) and git may come from homebrew, none of
# which a bare launchd PATH includes. Prepend the usual install folders before
# any dependency check so the popup works regardless of how it was launched.
herdr_popup_prepend_path() {
  for dir in \
    "$HOME/.local/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.nix-profile/bin" \
    "/etc/profiles/per-user/${USER:-$(id -un)}/bin" \
    "/opt/homebrew/bin" \
    "/usr/local/bin"
  do
    [ -d "$dir" ] && PATH="$dir:$PATH"
  done
  export PATH
}

# Echo the resolved herdr-projects binary, or nothing if it cannot be found.
# Resolution order:
# 1. $HERDR_PROJECTS_BIN (explicit override, what the e2e tests use);
# 2. the launcher shim the plugin writes into the data folder
#    (~/.herdr-projects/data/bin/herdr-projects) the first time the board opens
#    — upstream's blessed stable path ("so agents and hooks find it without
#    anything on their PATH"; the shim already pins the board's data/config
#    dirs, so it works even from a bare launchd environment);
# 3. a manual ~/.local/bin install;
# 4. the release asset bin/run.sh downloaded into the plugin checkout — this
#    exists right after `plugin install` even before the board has ever opened,
#    which is when a first-run prefix+shift+c registration happens;
# 5. whatever `command -v` finds on the (already prepended) PATH.
# Callers keep their own not-found handling (plain exit vs die) and wording.
herdr_projects_bin() {
  if [ -n "${HERDR_PROJECTS_BIN:-}" ] && [ -x "$HERDR_PROJECTS_BIN" ]; then
    printf '%s\n' "$HERDR_PROJECTS_BIN"
    return
  fi
  local shim
  shim="$(hp_home)/data/bin/herdr-projects"
  if [ -x "$shim" ]; then
    printf '%s\n' "$shim"
    return
  fi
  if [ -x "$HOME/.local/bin/herdr-projects" ]; then
    printf '%s\n' "$HOME/.local/bin/herdr-projects"
    return
  fi
  local os arch cfg plugin
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    *) os="" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) arch="" ;;
  esac
  cfg="${HERDR_CONFIG_DIR:-$HOME/.config/herdr}"
  if [ -n "$os" ] && [ -n "$arch" ]; then
    for plugin in "$cfg"/plugins/github/herdr-projects-* "$cfg"/plugins/herdr-projects-*; do
      [ -d "$plugin" ] || continue
      if [ -x "$plugin/bin/herdr-projects-$os-$arch" ]; then
        printf '%s\n' "$plugin/bin/herdr-projects-$os-$arch"
        return
      fi
    done
  fi
  command -v herdr-projects 2>/dev/null || true
}

# --- herdr-projects 1.2 data layout ------------------------------------------

# The data home: HERDR_PROJECTS_HOME names another folder, else the standard
# per-user ~/.herdr-projects (same default as the Rust binary itself).
hp_home() { printf '%s\n' "${HERDR_PROJECTS_HOME:-$HOME/.herdr-projects}"; }
hp_repos_file() { printf '%s\n' "$(hp_home)/data/repos.json"; }

# Pin the default for child processes once, so a popup launched with a bare
# environment and the CLI agree on the same data folder.
hp_export_env() { export HERDR_PROJECTS_HOME="$(hp_home)"; }

# One small python3 front-end over data/repos.json (a {name: path} JSON object
# the plugin maintains under its own flock). We never write that file from
# shell: registration goes through the public CLI (hp_register_repo below).
# Run from "/" with -I so a planted module in an arbitrary popup cwd cannot be
# imported; all inputs arrive as arguments.
_hp_repos_py() {
  ( cd / && python3 -I - "$(hp_repos_file)" "$@" <<'PY'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        repos = json.load(fh)
    if not isinstance(repos, dict):
        repos = {}
except OSError:
    repos = {}
except ValueError:
    repos = {}
def real(p):
    return os.path.realpath(os.path.expanduser(p))
if cmd == "name-for-path":
    # Longest registered repo path that contains the folder (the repo's own
    # dir or a worktree/subfolder of it); empty when none.
    p = real(sys.argv[3])
    best = ""
    for k, v in repos.items():
        rp = real(v)
        if (p == rp or p.startswith(rp.rstrip("/") + os.sep)) and len(rp) > len(best):
            best = rp
    if best:
        for k, v in repos.items():
            if real(v) == best:
                print(k)
                break
elif cmd == "list":
    for k in sorted(repos):
        print("%s\t%s" % (k, repos[k]))
elif cmd == "path":
    print(repos.get(sys.argv[3], ""))
PY
  )
}

# Echo the registered repo name whose checkout contains the given folder
# (longest-prefix match), or nothing.
hp_known_repo_for_path() { _hp_repos_py name-for-path "$1"; }

# Echo all known repos as name<TAB>path, sorted by name.
hp_list_known_repos() { _hp_repos_py list; }

# Echo a known repo's checkout path, or nothing when the name is not registered.
hp_repo_path() { _hp_repos_py path "$1"; }

# Registry names: ASCII letters/digits and _ . + - (mirrors store/repos.rs
# repo_of's basename sanitizer), up to 28 chars, with -2/-3 disambiguation.
hp_valid_repo_name() { case "$1" in ''|*[!A-Za-z0-9_.+-]*) return 1 ;; *) return 0 ;; esac; }

# Register one local checkout into data/repos.json WITHOUT leaving a task on
# the board: the plugin has no register-only command (a repo is "named on first
# sight"), so add a plain todo task — no --delegate, so no agent is ever
# started and herdr need not be running — and remove it at once. The repo
# entry persists. Idempotent; prints one status line. Args: <hp_bin> <path>.
hp_register_repo() {
  local hp="$1" path="$2" name out id
  name="$(hp_known_repo_for_path "$path")"
  if [ -n "$name" ]; then
    printf 'already registered: %s\n' "$name"
    return 0
  fi
  [ -d "$path" ] || { echo "not a directory: $path" >&2; return 1; }
  out="$("$hp" add "register local repository" --repo "$path" 2>&1)" || {
    printf '%s\n' "$out" >&2
    return 1
  }
  # Output is "<SHORTKEY>-<n>: added"; the short key names the same task as the
  # canonical repo/n id, so clear it directly.
  id="${out%%: added*}"
  case "$id" in
    ''|*[!A-Za-z0-9_.-]*) echo "unexpected add output: $out" >&2; return 1 ;;
  esac
  "$hp" clear "$id" >/dev/null 2>&1 || {
    echo "registration task $id could not be cleared" >&2
    return 1
  }
  name="$(hp_known_repo_for_path "$path")"
  printf 'registered: %s\n' "${name:-$path}"
}

# Absolute paths of local git checkouts under HP_PROJECT_ROOTS (colon-
# separated; default ~/Documents:~/.config), up to 4 levels deep. .git is a
# directory in a plain repo but a file in worktrees/submodules; match both.
hp_scan_local_repos() {
  local roots="${HP_PROJECT_ROOTS:-$HOME/Documents:$HOME/.config}" old_ifs root
  old_ifs=$IFS
  IFS=:
  for root in $roots; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 4 \( -type d -o -type f \) -name .git -prune 2>/dev/null |
      while IFS= read -r gitdir; do printf '%s\n' "${gitdir%/.git}"; done
  done
  IFS=$old_ifs
}

# Filter a stdin list of checkout paths, echoing only the ones the registry
# does not know yet (real-path compared, like the plugin's own lookup). Run
# from "/" with -I so a planted module in the popup cwd cannot be imported.
hp_filter_unknown_repos() {
  ( cd / && python3 -I -c '
import json, os, sys
home = os.environ.get("HERDR_PROJECTS_HOME") or os.path.expanduser("~/.herdr-projects")
try:
    with open(os.path.join(home, "data", "repos.json"), encoding="utf-8") as fh:
        repos = json.load(fh)
    if not isinstance(repos, dict):
        repos = {}
except (OSError, ValueError):
    repos = {}
known = {os.path.realpath(os.path.expanduser(p)) for p in repos.values()}
for line in sys.stdin:
    p = line.rstrip("\n")
    if p and os.path.realpath(os.path.expanduser(p)) not in known:
        print(p)
' )
}

# fzf over the registered repos; echoes the chosen repo name. Cancel (Esc),
# an empty selection, or an empty registry echo nothing and return 1 — callers
# that want the "empty registry" guidance must check the registry themselves
# first: a `die` inside this command substitution would only exit the subshell.
hp_pick_known_repo() {
  local prompt="$1" list selection name
  list="$(hp_list_known_repos)"
  [ -n "$list" ] || return 1
  selection="$(printf '%s\n' "$list" | fzf \
    --prompt="$prompt" \
    --header='Enter: choose   Esc: cancel')" || return 1
  [ -n "$selection" ] || return 1
  name="${selection%%$'\t'*}"
  hp_valid_repo_name "$name" || die "unexpected repo list output: $selection"
  [ -n "$(hp_repo_path "$name")" ] || die "repo vanished from the registry: $name"
  printf '%s\n' "$name"
}

# The pane a popup was launched for ("underlying tiled pane"); empty outside
# a popup (e.g. the script run straight from a shell).
hp_active_pane() { printf '%s\n' "${HERDR_ACTIVE_PANE_ID:-}"; }

# Cached `herdr agent list` JSON for this launcher run; empty on any failure.
hp_agent_list_json() {
  local sock="$1"
  if [ -z "${_hp_agent_list_fetched:-}" ]; then
    _hp_agent_list="$(HERDR_SOCKET_PATH="$sock" herdr agent list 2>/dev/null || true)"
    _hp_agent_list_fetched=1
  fi
  printf '%s' "$_hp_agent_list"
}

# Echo the cwd (fallback foreground_cwd) of a live pane, one line.
hp_pane_cwd() {
  local sock="$1" pane="$2"
  command -v jq >/dev/null 2>&1 || return 0
  hp_agent_list_json "$sock" | jq -r --arg p "$pane" \
    '.result.agents[]? | select(.pane_id == $p) | [.cwd, .foreground_cwd] | map(select(. != null and . != "")) | .[0] // ""' 2>/dev/null | head -1
}

# Resolve the repo for the current context: PWD inside a known checkout, then
# the active pane's cwd, then an fzf picker over the registry. Echoes the repo
# name and returns 0; on fzf cancel echoes nothing and returns 1.
hp_resolve_repo() {
  local name pane dir
  name="$(hp_known_repo_for_path "$PWD")"
  if [ -n "$name" ]; then printf '%s\n' "$name"; return 0; fi
  pane="$(hp_active_pane)"
  if [ -n "$pane" ]; then
    dir="$(hp_pane_cwd "$(hp_current_socket)" "$pane")"
    if [ -n "$dir" ]; then
      name="$(hp_known_repo_for_path "$dir")"
      if [ -n "$name" ]; then printf '%s\n' "$name"; return 0; fi
    fi
  fi
  command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"
  hp_pick_known_repo 'repo > '
}

# --- herdr sockets and coordinator state -------------------------------------

# Mirror the plugin's session_name(): the session folder is the segment between
# sessions/ and herdr.sock for a per-session socket, else "default".
hp_session_name() {
  local sock="$1"
  case "$sock" in
    */sessions/*/herdr.sock) printf '%s\n' "${sock%/herdr.sock}" | sed 's#.*/##' ;;
    *) printf 'default\n' ;;
  esac
}

# The herdr socket commands should talk to: the pinned env socket, else the
# XDG default (with HERDR_SESSION selecting a session socket) — same fallback
# order as the plugin's current_socket().
hp_current_socket() {
  if [ -n "${HERDR_SOCKET_PATH:-}" ]; then
    printf '%s\n' "$HERDR_SOCKET_PATH"
    return 0
  fi
  local base="${XDG_CONFIG_HOME:-$HOME/.config}"
  if [ -n "${HERDR_SESSION:-}" ]; then
    printf '%s/herdr/sessions/%s/herdr.sock\n' "$base" "$HERDR_SESSION"
  else
    printf '%s/herdr/herdr.sock\n' "$base"
  fi
}

# Path of a repo coordinator's state.json, preferring the current herdr session
# and otherwise the newest state folder; empty when no coordinator was ever
# started for the repo.
hp_coordinator_state_file() {
  local repo="$1" data_dir session f latest
  data_dir="$(hp_home)/data/coordinator"
  [ -d "$data_dir" ] || return 0
  session="$(hp_session_name "$(hp_current_socket)")"
  f="$data_dir/$session/projects/$repo/state.json"
  [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  latest="$(find "$data_dir" -maxdepth 4 -path "*/projects/$repo/state.json" -type f 2>/dev/null \
    -exec stat -f '%m %N' {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
  # GNU stat (Linux) has no -f '%m %N'; fall back to ls -t there.
  if [ -z "$latest" ]; then
    latest="$(find "$data_dir" -maxdepth 4 -path "*/projects/$repo/state.json" -type f -print0 2>/dev/null \
      | xargs -0 ls -t 2>/dev/null | head -1)"
  fi
  printf '%s\n' "$latest"
}

# Echo the repos that have any coordinator state (across all sessions), one per
# line, sorted and de-duped.
hp_state_repos() {
  local data_dir
  data_dir="$(hp_home)/data/coordinator"
  [ -d "$data_dir" ] || return 0
  find "$data_dir" -maxdepth 4 -path '*/projects/*/state.json' -type f 2>/dev/null \
    | sed 's#^.*/projects/##; s#/state.json$##' | sort -u
}

# Mirror co.rs agent_name() for a project coordinator: lowercase the repo, map
# every char outside [a-z0-9_] to '-', build "sw-coordinator-<tail>", cut the
# WHOLE string to 29 chars (room left for the -2/-3 disambiguation the pump
# appends when the name is taken) and trim trailing hyphens.
hp_coordinator_name_head() {
  local repo="$1" tail full
  tail="$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/-/g')"
  full="sw-coordinator-$tail"
  full="${full:0:29}"
  while [ -n "$full" ] && [ "${full: -1}" = "-" ]; do full="${full%?}"; done
  printf '%s\n' "$full"
}

# True when the pane is reachable on the given socket.
hp_pane_alive() {
  local sock="$1" pane="$2"
  [ -n "$pane" ] || return 1
  HERDR_SOCKET_PATH="$sock" herdr pane get "$pane" >/dev/null 2>&1
}

# Focus the repo's live coordinator pane. Tries the recorded pane in
# state.json first, then any live agent still carrying the sw-coordinator-<repo>
# name (head or head-N, the pump's disambiguation) with its cwd at the repo
# root, newest state_change_seq wins. Never starts anything.
# Echoes "focused" and returns 0 on success; echoes "none" and returns 1 when no
# live coordinator exists. Args: <repo>.
hp_focus_repo_coordinator() {
  local repo="$1" state_file sock pane root head agents target best_seq cid cname cseq
  state_file="$(hp_coordinator_state_file "$repo")"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    sock="$(jq -r '.socket // empty' "$state_file" 2>/dev/null || true)"
    pane="$(jq -r '.pane // empty' "$state_file" 2>/dev/null || true)"
  fi
  [ -n "${sock:-}" ] || sock="$(hp_current_socket)"
  if [ -n "${pane:-}" ] && hp_pane_alive "$sock" "$pane"; then
    HERDR_SOCKET_PATH="$sock" herdr agent focus "$pane" >/dev/null 2>&1 \
      && { printf 'focused\n'; return 0; }
  fi

  command -v jq >/dev/null 2>&1 || { printf 'none\n'; return 1; }
  root="$(hp_repo_path "$repo")"
  head="$(hp_coordinator_name_head "$repo")"
  target=""; best_seq=-1
  # The structural name test happens here in bash once per candidate; jq only
  # pre-filters panes at the repo root. cwd is the coordinator's repo folder
  # (task agents live in worktrees and carry different names anyway).
  agents="$(HERDR_SOCKET_PATH="$sock" herdr agent list 2>/dev/null || true)"
  [ -n "$agents" ] || { printf 'none\n'; return 1; }
  while IFS=$'\t' read -r cid cname cseq; do
    [ -n "$cid" ] || continue
    if [ "$cname" = "$head" ]; then :; else
      case "$cname" in
        "$head"-*)
          local n="${cname#"$head"-}"
          case "$n" in ''|*[!0-9]*) continue ;; esac
          [ "$n" -ge 1 ] 2>/dev/null || continue
          ;;
        *) continue ;;
      esac
    fi
    if [ "$cseq" -gt "$best_seq" ] 2>/dev/null; then best_seq="$cseq"; target="$cid"; fi
  done <<EOF
$(printf '%s' "$agents" | jq -r --arg root "$root" '
  .result.agents[]?
  | select((.cwd // "") == $root or (.foreground_cwd // "") == $root)
  | [.pane_id, (.name // ""), (.state_change_seq // 0)] | @tsv' 2>/dev/null || true)
EOF

  if [ -z "$target" ]; then printf 'none\n'; return 1; fi
  HERDR_SOCKET_PATH="$sock" herdr agent focus "$target" >/dev/null 2>&1 \
    && { printf 'focused\n'; return 0; }
  printf 'none\n'
  return 1
}

# Open a repo's project coordinator for the human: focus it when a live pane
# exists, restart the same conversation when state exists but the pane is gone,
# or start a fresh one on first use. The CLI only queues the request and kicks
# its own detached pump (which opens the tab), so it returns immediately; the
# popup can close. Args: <hp_bin> <repo>.
hp_open_repo_coordinator() {
  local hp="$1" repo="$2" status state_file action msg
  status="$(hp_focus_repo_coordinator "$repo")" && { printf '%s\n' "$status"; return 0; }
  state_file="$(hp_coordinator_state_file "$repo")"
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then action="restart"; else action="new"; fi
  msg="$("$hp" coordinator --project "$repo" "$action" 2>&1)" || {
    printf '%s\n' "$msg" >&2
    return 1
  }
  printf '%s\n' "$msg"
}
