#!/usr/bin/env bash
# e2e tests for the herdr-projects popup wrappers against the 1.2.x board
# model (new-project, pick-project, add-repo, new-coordinator,
# focus-coordinator).
#
# The REAL herdr-projects 1.2 binary handles repo registration offline
# (add+clear leaves data/repos.json); `coordinator` is intercepted by a stub
# that records args and can lay down state.json; fzf and herdr are stubbed as
# bash functions through BASH_ENV so the scripts' own PATH prepend cannot
# shadow them. Everything runs under mktemp -d; the real ~/.herdr-projects is
# never touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve a real herdr-projects >= 1.2 binary, in order:
#   1. $HERDR_PROJECTS_REAL_BIN if executable and reporting 1.2.x
#   2. downloaded release assets under the herdr plugins dir
#   3. target/release builds under the herdr plugins dir
#   4. herdr-projects on PATH
# A build of the OLD 0.2 fork fails the version filter and is skipped.
TRIED_PATHS=()
REAL_BIN=""
is_twelve() {
	"$1" version 2>/dev/null | grep -q '^herdr-projects 1\.2\.'
}
consider() {
	local c="$1"
	TRIED_PATHS+=("$c")
	if [ -x "$c" ] && { [ -z "$REAL_BIN" ] || [ "$c" -nt "$REAL_BIN" ]; } && is_twelve "$c"; then
		REAL_BIN="$c"
	fi
}
if [ -n "${HERDR_PROJECTS_REAL_BIN:-}" ]; then
	if [ -x "$HERDR_PROJECTS_REAL_BIN" ] && is_twelve "$HERDR_PROJECTS_REAL_BIN"; then
		REAL_BIN="$HERDR_PROJECTS_REAL_BIN"
	else
		TRIED_PATHS+=("$HERDR_PROJECTS_REAL_BIN (set, but not an executable 1.2.x binary)")
	fi
else
	os="$(uname -s | tr '[:upper:]' '[:lower:]')"
	case "$(uname -m)" in x86_64 | amd64) arch=x86_64 ;; aarch64 | arm64) arch=aarch64 ;; *) arch="" ;; esac
	for candidate in \
		"$HOME"/.config/herdr/plugins/github/herdr-projects-*/bin/herdr-projects-"$os"-"$arch" \
		"$HOME"/.config/herdr/plugins/github/herdr-projects-*/target/release/herdr-projects \
		; do
		[ -e "$candidate" ] && consider "$c"
	done
	if [ -z "$REAL_BIN" ]; then
		path_bin="$(command -v herdr-projects 2>/dev/null || true)"
		if [ -n "$path_bin" ]; then consider "$path_bin"; else TRIED_PATHS+=("herdr-projects (not on PATH)"); fi
	fi
fi

if [ -z "$REAL_BIN" ]; then
	echo "skipped: real herdr-projects 1.2.x binary not found; tried:"
	for p in "${TRIED_PATHS[@]}"; do
		echo "  $p"
	done
	exit 0
fi

# --- globals ---
PASS=0
FAIL=0
TEMP_DIRS=()
CASE_DONE=0
RC=0

cleanup_all() {
	for d in "${TEMP_DIRS[@]}"; do
		rm -rf "$d" 2>/dev/null || true
	done
}
trap cleanup_all EXIT

ok() { echo "case $1 OK"; PASS=$((PASS + 1)); CASE_DONE=1; }
ng() { echo "case $1 FAIL: $2" >&2; FAIL=$((FAIL + 1)); CASE_DONE=1; }

run_case() {
	local name="$1"
	CASE_DONE=0
	"$name" || true
	if [ "$CASE_DONE" = 0 ]; then
		echo "case $name CRASHED (set -e triggered before ok/ng)" >&2
		FAIL=$((FAIL + 1))
	fi
}

make_git_repo() {
	local path="$1"
	mkdir -p "$path"
	# Identity per-repo: run_wrapper later replaces HOME, so no global config
	# may be assumed.
	(cd "$path" \
		&& git init -q \
		&& git -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m init)
}

# Register a repo the way the launchers do (real binary, offline): placeholder
# task added without delegation and cleared immediately. Always pinned to the
# case data home: this runs BEFORE run_wrapper exports the env, and the real
# ~/.herdr-projects must never be touched.
seed_register() {
	local path="$1" out id
	out="$(HERDR_PROJECTS_HOME="$CASE_DATA" "$REAL_BIN" add "seed registration" --repo "$path")"
	id="${out%%: added*}"
	HERDR_PROJECTS_HOME="$CASE_DATA" "$REAL_BIN" clear "$id" >/dev/null
}

# Create a fresh case environment. Sets: CASE_T, CASE_BIN, CASE_HOME, CASE_WS,
# CASE_DATA (HERDR_PROJECTS_HOME).
setup_case() {
	CASE_T="$(mktemp -d)"
	TEMP_DIRS+=("$CASE_T")
	CASE_BIN="$CASE_T/bin"
	CASE_HOME="$CASE_T/home"
	CASE_WS="$CASE_T/ws"
	CASE_DATA="$CASE_HOME/.herdr-projects"
	mkdir -p "$CASE_BIN" "$CASE_HOME" "$CASE_WS"

	# Reset scenario env that would otherwise leak across sequential cases.
	unset HP_STUB_PICK HP_STUB_DEAD HP_STUB_CO_STATE HP_STUB_CO_SOCKET CASE_CWD
	HP_STUB_PICK=none

	# BASH_ENV: fzf + herdr as FUNCTIONS (functions win over PATH even after
	# the launchers prepend their install dirs).
	cat > "$CASE_T/bash_env.sh" <<'BASH_ENV'
fzf() {
	local input count pick_var pick n
	input="$(cat 2>/dev/null)" || input=""
	count=0
	if [ -f "${HP_STUB_FZF_COUNT:-/dev/null}" ]; then
		count="$(cat "${HP_STUB_FZF_COUNT}" 2>/dev/null)" || count=0
	fi
	count=$((count + 1))
	printf '%s' "$count" > "${HP_STUB_FZF_COUNT:-/dev/null}" 2>/dev/null || true
	pick_var="HP_STUB_PICK${count}"
	pick="${!pick_var:-${HP_STUB_PICK:-none}}"
	case "$pick" in
		first) printf '%s\n' "$input" | head -1 ;;
		last) printf '%s\n' "$input" | tail -1 ;;
		all) printf '%s\n' "$input" ;;
		head-*) n="${pick#head-}"; printf '%s\n' "$input" | head -n "$n" ;;
		capture)
			printf '%s\n' "$input" > "${HP_STUB_CAPTURE:-/dev/null}" 2>/dev/null || true
			return 1
			;;
		raw:*) printf '%s\n' "${pick#raw:}" ;;
		none) return 1 ;;
		*) printf '%s\n' "$input" | grep -Fx -- "$pick" || return 1 ;;
	esac
}
# Minimal herdr: pane liveness, agent focus (records the pinned socket), and a
# scripted agent list. Uses return, not exit: this is a BASH_ENV function, and
# a function called with a temporary-assignment prefix (HERDR_SOCKET_PATH=…
# herdr …) cannot exit the caller; with `exit` bash 5.2 even mis-resolves the
# call (127). The launchers call the real external herdr binary that way.
herdr() {
	local cmd sub id
	cmd="${1:-}"; sub="${2:-}"
	case "$cmd" in
		pane)
			[ "$sub" = "get" ] || return 0
			id="$3"
			case " ${HP_STUB_DEAD:-} " in *" $id "*) return 1 ;; esac
			return 0
			;;
		agent)
			case "$sub" in
				focus)
					id="$3"
					case " ${HP_STUB_DEAD:-} " in *" $id "*) return 1 ;; esac
					printf 'focus\t%s\t%s\n' "${HERDR_SOCKET_PATH:-}" "$id" >> "${HP_STUB_LOG:-/dev/null}"
					return 0
					;;
				list)
					if [ -f "${HP_STUB_AGENTS:-/dev/null}" ]; then cat "$HP_STUB_AGENTS"
					else echo '{"result":{"agents":[]}}'; fi
					return 0
					;;
			esac
			;;
	esac
	return 0
}
BASH_ENV

	# herdr-projects stub: delegate everything to the real binary except the
	# `coordinator` command, which is recorded and may materialize state.json
	# (HP_STUB_CO_STATE = pane id to record; HP_STUB_CO_SOCKET = its socket).
	cat > "$CASE_BIN/herdr-projects" <<'HP'
#!/usr/bin/env bash
set -euo pipefail
real_bin="${HP_STUB_REAL_BIN:?}"
args=("$@")
if [ "${1:-}" = "coordinator" ]; then
	repo=""; action=""
	for ((i = 1; i < ${#args[@]}; i++)); do
		case "${args[$i]}" in
			--project) repo="${args[$((i + 1))]}" ;;
			new|restart|tell|stop|where|status) action="${args[$i]}" ;;
		esac
	done
	[ -z "$action" ] && action="status"
	printf 'coordinator\t%s\t%s\n' "$repo" "$action" >> "${HP_STUB_LOG:?}"
	if { [ "$action" = new ] || [ "$action" = restart ]; } && [ -n "${HP_STUB_CO_STATE:-}" ]; then
		sock="${HP_STUB_CO_SOCKET:-${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}}"
		case "$sock" in
			*/sessions/*/herdr.sock) session="${sock%/herdr.sock}"; session="${session##*/}" ;;
			*) session="default" ;;
		esac
		dir="$HERDR_PROJECTS_HOME/data/coordinator/$session/projects/$repo"
		mkdir -p "$dir"
		printf '{"socket":"%s","pane":"%s","run":{"kind":"claude"}}' "$sock" "$HP_STUB_CO_STATE" > "$dir/state.json"
	fi
	echo "a new $repo coordinator is starting"
	exit 0
fi
exec "$real_bin" "$@"
HP
	chmod +x "$CASE_BIN/herdr-projects"

	: > "$CASE_T/hp_log"
	echo 0 > "$CASE_T/fzf_count"
}

# Run a wrapper script inside the case environment. Cwd is $CASE_CWD (default
# the case root), so cwd-based repo resolution can be tested.
run_wrapper() {
	local script="$1"
	export HOME="$CASE_HOME"
	export HERDR_PROJECTS_BIN="$CASE_BIN/herdr-projects"
	export HERDR_PROJECTS_HOME="$CASE_DATA"
	export HP_PROJECT_ROOTS="$CASE_WS"
	export HP_STUB_REAL_BIN="$REAL_BIN"
	export HP_STUB_FZF_COUNT="$CASE_T/fzf_count"
	export HP_STUB_LOG="$CASE_T/hp_log"
	export HP_STUB_CAPTURE="$CASE_T/captured"
	export HP_STUB_AGENTS="$CASE_T/agents.json"
	export HP_STUB_DEAD="${HP_STUB_DEAD:-}"
	export HP_STUB_CO_STATE="${HP_STUB_CO_STATE:-}"
	export HP_STUB_CO_SOCKET="${HP_STUB_CO_SOCKET:-}"
	export BASH_ENV="$CASE_T/bash_env.sh"
	export PATH="$CASE_BIN:/usr/bin:/bin"
	( cd "${CASE_CWD:-$CASE_T}" && bash "$REPO_ROOT/config/herdr/$script" )
}

pipe_run() { # <stdin text> <wrapper...>
	local stdin_str="$1"; shift
	RC=0
	printf '%s\n' "$stdin_str" | "$@" > "$CASE_T/out" 2> "$CASE_T/err" || RC=$?
}
null_run() {
	RC=0
	"$@" < /dev/null > "$CASE_T/out" 2> "$CASE_T/err" || RC=$?
}

log_has() { grep -Fq -- "$1" "$CASE_T/hp_log" 2>/dev/null; }

# Write a coordinator state.json by hand (the stub only writes one when the
# coordinator command is allowed to).
write_state() { # <session> <repo> <socket> <pane>
	local dir="$CASE_DATA/data/coordinator/$1/projects/$2"
	mkdir -p "$dir"
	printf '{"socket":"%s","pane":"%s","run":{"kind":"claude"}}' "$3" "$4" > "$dir/state.json"
}

# --- cases: new-project / add-repo (registration) ----------------------------

# 1. new-project: one picked repo -> registered, no tasks left, coordinator new
case_new_one() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	export HP_STUB_PICK=first HP_STUB_CO_STATE=P1
	null_run run_wrapper new-project.sh
	[ "$RC" = 0 ] || { ng "new-one" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq '"repo-a"' "$CASE_DATA/data/repos.json" || { ng "new-one" "repo-a not registered"; return; }
	[ -f "$CASE_DATA/data/tasks/repo-a/1/task.json" ] && { ng "new-one" "placeholder task survived"; return; }
	log_has "coordinator	repo-a	new" || { ng "new-one" "coordinator new not logged: $(cat "$CASE_T/hp_log")"; return; }
	ok "new-one"
}

# 2. new-project: multi pick registers every repo, coordinator only for first
case_new_multi() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"; make_git_repo "$CASE_WS/repo-b"
	export HP_STUB_PICK=all HP_STUB_CO_STATE=P1
	null_run run_wrapper new-project.sh
	[ "$RC" = 0 ] || { ng "new-multi" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq '"repo-a"' "$CASE_DATA/data/repos.json" || { ng "new-multi" "repo-a missing"; return; }
	grep -Fq '"repo-b"' "$CASE_DATA/data/repos.json" || { ng "new-multi" "repo-b missing"; return; }
	n="$(grep -c '^coordinator' "$CASE_T/hp_log")"
	[ "$n" = 1 ] || { ng "new-multi" "expected exactly 1 coordinator start, got $n"; return; }
	log_has "coordinator	repo-a	new" || { ng "new-multi" "first repo must start the coordinator"; return; }
	ok "new-multi"
}

# 3. new-project: fzf cancel -> exit 0, nothing registered
case_new_cancel() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	export HP_STUB_PICK=none
	null_run run_wrapper new-project.sh
	[ "$RC" = 0 ] || { ng "new-cancel" "rc=$RC"; return; }
	[ -e "$CASE_DATA/data/repos.json" ] && { ng "new-cancel" "registry touched on cancel"; return; }
	ok "new-cancel"
}

# 4. worktree checkouts (.git files) show up in the candidates
case_worktree() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	(cd "$CASE_WS/repo-a" && git worktree add -q wt-a 2>/dev/null)
	export HP_STUB_PICK=capture
	null_run run_wrapper add-repo.sh
	[ "$RC" = 0 ] || { ng "worktree" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq "wt-a" "$CASE_T/captured" || { ng "worktree" "wt-a missing from candidates"; return; }
	ok "worktree"
}

# 5. add-repo: already-registered checkouts are hidden, the new one registers
case_add_new() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"; make_git_repo "$CASE_WS/repo-b"
	seed_register "$CASE_WS/repo-a"
	export HP_STUB_PICK=capture
	null_run run_wrapper add-repo.sh
	# capture mode returns 1 (cancel), so the script exits before registering;
	# the assertion is only about the offered candidates: exactly repo-b.
	[ "$(cat "$CASE_T/captured" 2>/dev/null)" = "$CASE_WS/repo-b" ] \
		|| { ng "add-new" "candidates should be exactly repo-b, got: $(cat "$CASE_T/captured" 2>/dev/null)"; return; }
	ok "add-new"
}

# 6. add-repo: pick and actually register the unknown repo
case_add_register() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"; make_git_repo "$CASE_WS/repo-b"
	seed_register "$CASE_WS/repo-a"
	export HP_STUB_PICK=last
	null_run run_wrapper add-repo.sh
	[ "$RC" = 0 ] || { ng "add-register" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq '"repo-b"' "$CASE_DATA/data/repos.json" || { ng "add-register" "repo-b not registered"; return; }
	ok "add-register"
}

# 7. add-repo: nothing new under the roots -> dies
case_add_all_known() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	export HP_STUB_PICK=first
	null_run run_wrapper add-repo.sh
	[ "$RC" != 0 ] || { ng "add-all-known" "expected failure when every repo is registered"; return; }
	grep -Fqi "already registered" "$CASE_T/err" || { ng "add-all-known" "err: $(cat "$CASE_T/err")"; return; }
	ok "add-all-known"
}

# --- cases: pick-project (focus / restart / new) ------------------------------

# 8. pick-project: empty registry -> dies with guidance, no fzf
case_pick_empty() {
	setup_case
	export HP_STUB_PICK=first
	null_run run_wrapper pick-project.sh
	[ "$RC" != 0 ] || { ng "pick-empty" "expected failure with empty registry"; return; }
	grep -Fqi "no registered repos" "$CASE_T/err" || { ng "pick-empty" "err: $(cat "$CASE_T/err")"; return; }
	ok "pick-empty"
}

# 9. pick-project: live recorded pane -> focus with the state's pinned socket
case_pick_focus() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	write_state default repo-a "/tmp/other-session.sock" P1
	export HP_STUB_PICK=first HP_STUB_CO_STATE=""
	null_run run_wrapper pick-project.sh
	[ "$RC" = 0 ] || { ng "pick-focus" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq "focus	/tmp/other-session.sock	P1" "$CASE_T/hp_log" || { ng "pick-focus" "focus not logged with pinned socket: $(cat "$CASE_T/hp_log")"; return; }
	if log_has "coordinator"; then ng "pick-focus" "must not start/restart a live coordinator"; return; fi
	ok "pick-focus"
}

# 10. pick-project: state exists but pane dead -> restart, not new
case_pick_restart() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	write_state default repo-a "$CASE_HOME/.config/herdr/herdr.sock" P1
	export HP_STUB_PICK=first HP_STUB_DEAD="P1" HP_STUB_CO_STATE=""
	null_run run_wrapper pick-project.sh
	[ "$RC" = 0 ] || { ng "pick-restart" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	log_has "coordinator	repo-a	restart" || { ng "pick-restart" "restart not logged: $(cat "$CASE_T/hp_log")"; return; }
	ok "pick-restart"
}

# 11. pick-project: no state yet -> new
case_pick_new() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	export HP_STUB_PICK=first HP_STUB_CO_STATE=""
	null_run run_wrapper pick-project.sh
	[ "$RC" = 0 ] || { ng "pick-new" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	log_has "coordinator	repo-a	new" || { ng "pick-new" "new not logged: $(cat "$CASE_T/hp_log")"; return; }
	ok "pick-new"
}

# --- cases: new-coordinator ---------------------------------------------------

# 12. new-coordinator resolves the repo from cwd without opening fzf
case_newco_cwd() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	export HP_STUB_PICK=none HP_STUB_CO_STATE="" CASE_CWD="$CASE_WS/repo-a"
	null_run run_wrapper new-coordinator.sh
	[ "$RC" = 0 ] || { ng "newco-cwd" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	log_has "coordinator	repo-a	new" || { ng "newco-cwd" "new not logged: $(cat "$CASE_T/hp_log")"; return; }
	# fzf must not have been consulted
	[ "$(cat "$CASE_T/fzf_count")" = 0 ] || { ng "newco-cwd" "fzf was used despite cwd match"; return; }
	ok "newco-cwd"
}

# --- cases: focus-coordinator (kept local feature) ----------------------------

# 13. focus: cross-session state pins HERDR_SOCKET_PATH for the focus call
case_focus_pinned_socket() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	write_state default repo-a "/tmp/socket-elsewhere.sock" P2
	export CASE_CWD="$CASE_WS/repo-a"
	null_run run_wrapper focus-coordinator.sh
	[ "$RC" = 0 ] || { ng "focus-pinned" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq "focus	/tmp/socket-elsewhere.sock	P2" "$CASE_T/hp_log" || { ng "focus-pinned" "$(cat "$CASE_T/hp_log")"; return; }
	ok "focus-pinned"
}

# 14. focus: recorded pane dead -> sw-coordinator-<repo> family fallback
case_focus_family() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	write_state default repo-a "$CASE_HOME/.config/herdr/herdr.sock" P1
	# P1 dead; P9 is the disambiguated coordinator at the repo root.
	cat > "$CASE_T/agents.json" <<JSON
{"result":{"agents":[
  {"pane_id":"P8","name":"sw-coordinator-other","cwd":"/elsewhere","state_change_seq":9},
  {"pane_id":"P9","name":"sw-coordinator-repo-a-2","cwd":"$CASE_WS/repo-a","foreground_cwd":"$CASE_WS/repo-a","state_change_seq":5}
]}}
JSON
	export HP_STUB_DEAD="P1" CASE_CWD="$CASE_WS/repo-a"
	null_run run_wrapper focus-coordinator.sh
	[ "$RC" = 0 ] || { ng "focus-family" "rc=$RC, err: $(cat "$CASE_T/err")"; return; }
	grep -Fq "focus	$CASE_HOME/.config/herdr/herdr.sock	P9" "$CASE_T/hp_log" \
		|| { ng "focus-family" "family fallback did not focus P9: $(cat "$CASE_T/hp_log")"; return; }
	ok "focus-family"
}

# 15. focus: nothing live -> non-zero and guidance, never starts a coordinator
case_focus_none() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	seed_register "$CASE_WS/repo-a"
	write_state default repo-a "$CASE_HOME/.config/herdr/herdr.sock" P1
	export HP_STUB_DEAD="P1" CASE_CWD="$CASE_WS/repo-a"
	null_run run_wrapper focus-coordinator.sh
	[ "$RC" != 0 ] || { ng "focus-none" "expected failure when no coordinator is live"; return; }
	grep -Fqi "no live coordinator" "$CASE_T/out" || { ng "focus-none" "out: $(cat "$CASE_T/out")"; return; }
	if log_has "coordinator"; then ng "focus-none" "focus must never start a coordinator"; return; fi
	ok "focus-none"
}

# 16. focus: no state anywhere and unknown cwd -> dies, no fzf crash
case_focus_never() {
	setup_case
	export HP_STUB_PICK=first
	null_run run_wrapper focus-coordinator.sh
	[ "$RC" != 0 ] || { ng "focus-never" "expected failure"; return; }
	grep -Fqi "no project coordinator" "$CASE_T/err" || { ng "focus-never" "err: $(cat "$CASE_T/err")"; return; }
	ok "focus-never"
}

# Binary resolution in herdr_projects_bin() needs no running herdr or the real
# binary's behaviour, only executable markers; check each probe tier directly.
# Call after setup_case + fixture creation. Extra args are NAME=VALUE pairs
# exported inside the resolving subshell.
resolve_bin() {
	(
		cd /
		unset HERDR_PROJECTS_BIN HERDR_PROJECTS_HOME
		export HOME="$CASE_HOME" USER="${USER:-$(id -un)}"
		export PATH="/usr/bin:/bin"
		[ "$#" -gt 0 ] && export "$@"
		# shellcheck source=/dev/null
		. "$REPO_ROOT/config/herdr/herdr-popup-lib.sh"
		herdr_projects_bin
	)
}

# 17. the data-folder launcher shim (written when the board first opens) wins
# over the plugin-checkout release asset.
case_bin_shim() {
	setup_case
	local os arch got
	case "$(uname -s)" in Linux) os=linux ;; Darwin) os=macos ;; *) os=? ;; esac
	case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; *) arch=? ;; esac
	mkdir -p "$CASE_HOME/.herdr-projects/data/bin"
	printf '#!/bin/sh\nexit 0\n' > "$CASE_HOME/.herdr-projects/data/bin/herdr-projects"
	chmod +x "$CASE_HOME/.herdr-projects/data/bin/herdr-projects"
	mkdir -p "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-deadbeef/bin"
	printf '#!/bin/sh\nexit 0\n' > "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-deadbeef/bin/herdr-projects-$os-$arch"
	chmod +x "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-deadbeef/bin/herdr-projects-$os-$arch"
	got="$(resolve_bin)"
	[ "$got" = "$CASE_HOME/.herdr-projects/data/bin/herdr-projects" ] \
		|| { ng "bin-shim" "got: $got"; return; }
	ok "bin-shim"
}

# 18. fresh plugin install, board never opened: fall back to the release asset
# bin/run.sh downloaded into the plugin checkout.
case_bin_plugin_asset() {
	setup_case
	local os arch got
	case "$(uname -s)" in Linux) os=linux ;; Darwin) os=macos ;; *) os=? ;; esac
	case "$(uname -m)" in x86_64|amd64) arch=x86_64 ;; aarch64|arm64) arch=aarch64 ;; *) arch=? ;; esac
	mkdir -p "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-b1278ffb803c/bin"
	printf '#!/bin/sh\nexit 0\n' > "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-b1278ffb803c/bin/herdr-projects-$os-$arch"
	chmod +x "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-b1278ffb803c/bin/herdr-projects-$os-$arch"
	got="$(resolve_bin)"
	[ "$got" = "$CASE_HOME/.config/herdr/plugins/github/herdr-projects-b1278ffb803c/bin/herdr-projects-$os-$arch" ] \
		|| { ng "bin-plugin-asset" "got: $got"; return; }
	ok "bin-plugin-asset"
}

# 19. HERDR_PROJECTS_BIN override always wins.
case_bin_override() {
	setup_case
	local got
	mkdir -p "$CASE_HOME/.herdr-projects/data/bin"
	printf '#!/bin/sh\nexit 0\n' > "$CASE_HOME/.herdr-projects/data/bin/herdr-projects"
	chmod +x "$CASE_HOME/.herdr-projects/data/bin/herdr-projects"
	got="$(resolve_bin HERDR_PROJECTS_BIN="$CASE_BIN/herdr-projects")"
	[ "$got" = "$CASE_BIN/herdr-projects" ] \
		|| { ng "bin-override" "got: $got"; return; }
	ok "bin-override"
}

for c in \
	case_new_one case_new_multi case_new_cancel case_worktree \
	case_add_new case_add_register case_add_all_known \
	case_pick_empty case_pick_focus case_pick_restart case_pick_new \
	case_newco_cwd \
	case_focus_pinned_socket case_focus_family case_focus_none case_focus_never \
	case_bin_shim case_bin_plugin_asset case_bin_override \
	; do
	run_case "$c"
done

echo ""
echo "e2e summary: $PASS passed, $FAIL failed"

[ "$FAIL" -eq 0 ] || exit 1
echo "herdr pickers e2e test OK"
