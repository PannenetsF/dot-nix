#!/usr/bin/env bash
# e2e tests for herdr picker wrapper scripts (new-project, pick-project,
# add-repo). Uses the real herdr-projects binary with a stub fzf (defined via
# BASH_ENV so the script's own PATH block cannot shadow it) and a stub
# herdr-projects wrapper that intercepts open/list. Everything runs under
# mktemp -d; the real ~/.herdr-projects is never touched.
set -euo pipefail

REAL_BIN="/Users/bytedance/.config/herdr/plugins/github/herdr-projects-b1278ffb803c/target/release/herdr-projects"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -x "$REAL_BIN" ]; then
	echo "skipped: herdr-projects real binary not found at $REAL_BIN"
	exit 0
fi

# --- globals ---
PASS=0
FAIL=0
TEMP_DIRS=()
CASE_DONE=0
RC=0

# --- cleanup ---
cleanup_all() {
	for d in "${TEMP_DIRS[@]}"; do
		rm -rf "$d" 2>/dev/null || true
	done
}
trap cleanup_all EXIT

# --- helpers ---

ok() {
	echo "case $1 OK"
	PASS=$((PASS + 1))
	CASE_DONE=1
}

ng() {
	echo "case $1 FAIL: $2" >&2
	FAIL=$((FAIL + 1))
	CASE_DONE=1
}

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
	(cd "$path" && git init -q && git commit -q --allow-empty -m init)
}

# Create a fresh case environment: temp dir, stub bin dir, workspace, root.
# Sets: CASE_T, CASE_BIN, CASE_WS, CASE_ROOT
setup_case() {
	CASE_T="$(mktemp -d)"
	TEMP_DIRS+=("$CASE_T")
	CASE_BIN="$CASE_T/bin"
	CASE_WS="$CASE_T/ws"
	CASE_ROOT="$CASE_T/root"
	mkdir -p "$CASE_BIN" "$CASE_WS" "$CASE_ROOT"

	# BASH_ENV file: defines fzf as a function so the wrapper script's PATH
	# block cannot shadow it. Sourced before each script run.
	cat > "$CASE_T/bash_env.sh" <<'BASH_ENV'
# fzf stub function — reads candidates from stdin, selects per HP_STUB_PICK<call#>
# or HP_STUB_PICK. Modes: first, last, all, head-N, capture, raw:<line>, none,
# or a literal line to match (grep -Fx).
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
		first)
			printf '%s\n' "$input" | head -1
			;;
		last)
			printf '%s\n' "$input" | tail -1
			;;
		all)
			printf '%s\n' "$input"
			;;
		head-*)
			n="${pick#head-}"
			printf '%s\n' "$input" | head -n "$n"
			;;
		capture)
			printf '%s\n' "$input" > "${HP_STUB_CAPTURE:-/dev/null}" 2>/dev/null || true
			return 1
			;;
		raw:*)
			printf '%s\n' "${pick#raw:}"
			;;
		none)
			return 1
			;;
		*)
			printf '%s\n' "$input" | grep -Fx -- "$pick" || return 1
			;;
	esac
}
BASH_ENV

	# herdr-projects stub: delegates to the real binary except open/list,
	# which are scenario-controlled via HP_STUB_OPEN_MODE / HP_STUB_LIST_MODE.
	cat > "$CASE_BIN/herdr-projects" <<'HP'
#!/usr/bin/env bash
set -euo pipefail
real_bin="${HP_STUB_REAL_BIN:?}"
export PATH="/usr/bin:/bin:${PATH:-}"
args=("$@")
root=""
subcmd=""
i=0
while [ $i -lt ${#args[@]} ]; do
	case "${args[$i]}" in
		--root)
			root="${args[$((i + 1))]}"
			i=$((i + 2))
			;;
		*)
			subcmd="${args[$i]}"
			break
			;;
	esac
done
case "$subcmd" in
	open)
		mode="${HP_STUB_OPEN_MODE:-success}"
		case "$mode" in
			success)
				printf 'open: %s\n' "${args[*]}" >> "${HP_STUB_LOG:-/dev/null}"
				exit 0
				;;
			rebind)
				if printf '%s\n' "${args[*]}" | grep -q -- '--rebind'; then
					printf 'open-rebind: %s\n' "${args[*]}" >> "${HP_STUB_LOG:-/dev/null}"
					exit 0
				else
					echo "herdr-projects: recorded socket /tmp/fake-socket no longer exists" >&2
					exit 1
				fi
				;;
			fail)
				echo "herdr-projects: some other error" >&2
				exit 1
				;;
		esac
		;;
	list)
		mode="${HP_STUB_LIST_MODE:-real}"
		case "$mode" in
			real)
				exec "$real_bin" --root "$root" list
				;;
			malformed)
				printf 'Bad Slug\tx\ty\n'
				exit 0
				;;
		esac
		;;
	*)
		exec "$real_bin" "$@"
		;;
esac
HP
	chmod +x "$CASE_BIN/herdr-projects"
}

# Run a wrapper script with the case environment.
# The caller sets HP_STUB_PICK / HP_STUB_OPEN_MODE / HP_STUB_LIST_MODE etc.
# before calling. Stdin is inherited from the caller.
run_wrapper() {
	local script="$1"
	export HERDR_PROJECTS_BIN="$CASE_BIN/herdr-projects"
	export HERDR_PROJECTS_ROOT="$CASE_ROOT"
	export HP_PROJECT_ROOTS="$CASE_WS"
	export HP_STUB_REAL_BIN="$REAL_BIN"
	export HP_STUB_FZF_COUNT="$CASE_T/fzf_count"
	export HP_STUB_LOG="$CASE_T/hp_log"
	export HP_STUB_CAPTURE="$CASE_T/captured"
	export BASH_ENV="$CASE_T/bash_env.sh"
	bash "$REPO_ROOT/config/herdr/$script"
}

# Run a wrapper with stdin from a string, capture stdout/stderr to CASE_T.
# Sets RC.
pipe_run() {
	local stdin_str="$1"; shift
	RC=0
	printf '%s\n' "$stdin_str" | "$@" > "$CASE_T/out" 2> "$CASE_T/err" || RC=$?
}

# Run a wrapper with stdin from /dev/null, capture stdout/stderr to CASE_T.
# Sets RC.
null_run() {
	RC=0
	"$@" < /dev/null > "$CASE_T/out" 2> "$CASE_T/err" || RC=$?
}

# --- test cases ---

# 1. new-project: "Erdos" -> slug "erdos", PROJECT.md name = "Erdos"
case_new_erdos() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	export HP_STUB_PICK=first
	pipe_run "Erdos" run_wrapper new-project.sh
	if [ "$RC" -ne 0 ]; then
		ng "new-erdos" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq 'name = "Erdos"' "$CASE_ROOT/erdos/PROJECT.md" 2>/dev/null; then
		ng "new-erdos" "PROJECT.md missing name = \"Erdos\""
		return
	fi
	if ! grep -Fq "erdos" "$CASE_T/hp_log" 2>/dev/null; then
		ng "new-erdos" "stub open not called with erdos"
		return
	fi
	ok "new-erdos"
}

# 2. new-project: "My Project" -> slug "my-project", display name preserved
case_new_spaces() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	export HP_STUB_PICK=first
	pipe_run "My Project" run_wrapper new-project.sh
	if [ "$RC" -ne 0 ]; then
		ng "new-spaces" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq 'name = "My Project"' "$CASE_ROOT/my-project/PROJECT.md" 2>/dev/null; then
		ng "new-spaces" "PROJECT.md missing name = \"My Project\""
		return
	fi
	if ! grep -Fq "my-project" "$CASE_T/hp_log" 2>/dev/null; then
		ng "new-spaces" "stub open not called with my-project"
		return
	fi
	ok "new-spaces"
}

# 3. new-project: "-dash" -> slug "dash"
case_new_dash() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	export HP_STUB_PICK=first
	pipe_run "-dash" run_wrapper new-project.sh
	if [ "$RC" -ne 0 ]; then
		ng "new-dash" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq "dash" "$CASE_T/hp_log" 2>/dev/null; then
		ng "new-dash" "stub open not called with dash"
		return
	fi
	ok "new-dash"
}

# 4. new-project: repo path contains @ -> die, no project created
case_at_guard() {
	setup_case
	make_git_repo "$CASE_WS/foo@bar"
	export HP_STUB_PICK=first
	pipe_run "TestProject" run_wrapper new-project.sh
	if [ "$RC" -eq 0 ]; then
		ng "at-guard" "expected non-zero exit for @ in repo path"
		return
	fi
	if ! grep -Fq '@' "$CASE_T/err"; then
		ng "at-guard" "stderr missing @, got: $(cat "$CASE_T/err")"
		return
	fi
	# No project directory should have been created
	if [ -n "$(find "$CASE_ROOT" -mindepth 1 2>/dev/null)" ]; then
		ng "at-guard" "project directory created despite @ guard"
		return
	fi
	ok "at-guard"
}

# 5. new-project: duplicate name -> already-exists/attach path, open called
case_duplicate() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	# Pre-create the project
	"$REAL_BIN" --root "$CASE_ROOT" new --repo "$CASE_WS/repo-a" -- "Erdos" > /dev/null 2>&1
	export HP_STUB_PICK=first
	pipe_run "Erdos" run_wrapper new-project.sh
	if [ "$RC" -ne 0 ]; then
		ng "duplicate" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq "erdos" "$CASE_T/hp_log" 2>/dev/null; then
		ng "duplicate" "stub open not called"
		return
	fi
	ok "duplicate"
}

# 6. add-repo: attach repo-a to project that already has it -> idempotent (rc=0)
case_add_repo_idempotent() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	# Pre-create project with repo-a
	"$REAL_BIN" --root "$CASE_ROOT" new --repo "$CASE_WS/repo-a" -- "testproj" > /dev/null 2>&1
	export HP_STUB_PICK=first
	export HP_STUB_PICK2="raw:$CASE_WS/repo-a"
	null_run run_wrapper add-repo.sh
	if [ "$RC" -ne 0 ]; then
		ng "add-repo-idempotent" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	ok "add-repo-idempotent"
}

# 7. add-repo: attach repo-b (new) -> normal attached
case_add_repo_new() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	make_git_repo "$CASE_WS/repo-b"
	"$REAL_BIN" --root "$CASE_ROOT" new --repo "$CASE_WS/repo-a" -- "testproj" > /dev/null 2>&1
	export HP_STUB_PICK=first
	export HP_STUB_PICK2="raw:$CASE_WS/repo-b"
	null_run run_wrapper add-repo.sh
	if [ "$RC" -ne 0 ]; then
		ng "add-repo-new" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq "attached" "$CASE_T/out"; then
		ng "add-repo-new" "output missing 'attached', got: $(cat "$CASE_T/out")"
		return
	fi
	ok "add-repo-new"
}

# 8. worktree: .git file in worktree must appear in list_repos candidates
case_worktree() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	(cd "$CASE_WS/repo-a" && git worktree add -q wt-a 2>/dev/null)
	export HP_STUB_PICK=capture
	null_run run_wrapper new-project.sh
	# RC=0 because fzf cancel -> exit 0
	if [ "$RC" -ne 0 ]; then
		ng "worktree" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq "wt-a" "$CASE_T/captured" 2>/dev/null; then
		ng "worktree" "wt-a not in candidates: $(cat "$CASE_T/captured" 2>/dev/null)"
		return
	fi
	ok "worktree"
}

# 9. --rebind: open fails with "no longer exists" -> retry with --rebind -> rc=0
case_rebind() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	"$REAL_BIN" --root "$CASE_ROOT" new --repo "$CASE_WS/repo-a" -- "testproj" > /dev/null 2>&1
	export HP_STUB_PICK=first
	export HP_STUB_OPEN_MODE=rebind
	null_run run_wrapper pick-project.sh
	if [ "$RC" -ne 0 ]; then
		ng "rebind" "rc=$RC, stderr: $(cat "$CASE_T/err")"
		return
	fi
	if ! grep -Fq "open-rebind" "$CASE_T/hp_log" 2>/dev/null; then
		ng "rebind" "stub open-rebind not called"
		return
	fi
	ok "rebind"
}

# 10. open ordinary failure (no "no longer exists") -> rc!=0
case_open_fail() {
	setup_case
	make_git_repo "$CASE_WS/repo-a"
	"$REAL_BIN" --root "$CASE_ROOT" new --repo "$CASE_WS/repo-a" -- "testproj" > /dev/null 2>&1
	export HP_STUB_PICK=first
	export HP_STUB_OPEN_MODE=fail
	null_run run_wrapper pick-project.sh
	if [ "$RC" -eq 0 ]; then
		ng "open-fail" "expected non-zero exit for ordinary open failure"
		return
	fi
	ok "open-fail"
}

# 11. list guard (pick-project): malformed TSV -> die with "unexpected"
case_list_guard_pick() {
	setup_case
	export HP_STUB_PICK=first
	export HP_STUB_LIST_MODE=malformed
	null_run run_wrapper pick-project.sh
	if [ "$RC" -eq 0 ]; then
		ng "list-guard-pick" "expected non-zero exit for malformed list"
		return
	fi
	if ! grep -Fqi "unexpected" "$CASE_T/err"; then
		ng "list-guard-pick" "stderr missing 'unexpected', got: $(cat "$CASE_T/err")"
		return
	fi
	ok "list-guard-pick"
}

# 12. list guard (add-repo): malformed TSV -> die at project selection
case_list_guard_add() {
	setup_case
	export HP_STUB_PICK=first
	export HP_STUB_LIST_MODE=malformed
	null_run run_wrapper add-repo.sh
	if [ "$RC" -eq 0 ]; then
		ng "list-guard-add" "expected non-zero exit for malformed list"
		return
	fi
	if ! grep -Fqi "unexpected" "$CASE_T/err"; then
		ng "list-guard-add" "stderr missing 'unexpected', got: $(cat "$CASE_T/err")"
		return
	fi
	ok "list-guard-add"
}

# --- run all cases ---

run_case case_new_erdos
run_case case_new_spaces
run_case case_new_dash
run_case case_at_guard
run_case case_duplicate
run_case case_add_repo_idempotent
run_case case_add_repo_new
run_case case_worktree
run_case case_rebind
run_case case_open_fail
run_case case_list_guard_pick
run_case case_list_guard_add

echo ""
echo "e2e summary: $PASS passed, $FAIL failed"

# Verify the real ~/.herdr-projects was not touched (read-only check).
echo ""
echo "real ~/.herdr-projects check (read-only):"
if [ -d "$HOME/.herdr-projects" ]; then
	count=$(ls -A "$HOME/.herdr-projects" 2>/dev/null | wc -l | tr -d ' ')
	echo "  exists with $count entries (not modified by tests)"
else
	echo "  does not exist (not modified by tests)"
fi

[ "$FAIL" -eq 0 ] || exit 1
echo "herdr pickers e2e test OK"
