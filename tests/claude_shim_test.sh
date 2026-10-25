#!/usr/bin/env bash
# Stubbed tests for the claude trust shim: no real claude launch, no real
# ~/.claude.json. Validates trust-flag preseeding across plain dirs, git
# repos and linked worktrees, passthrough to the real binary, and that a
# missing real binary exits 127.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shim="${repo_root}/config/claude/claude-shim.sh"

failures=0
check() { # desc expected actual
  if [ "$2" != "$3" ]; then
    echo "FAIL: $1"
    echo "  expected: $2"
    echo "  actual:   $3"
    failures=$((failures + 1))
  else
    echo "ok: $1"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake PATH: a tools dir (jq) + a bin dir holding the "real" claude, then the
# shim dir copied in as its own directory. HOME points at the sandbox.
work="$tmp/home"
mkdir -p "$work" "$tmp/tools" "$tmp/bin" "$tmp/shimdir"
ln -s "$(command -v jq)" "$tmp/tools/jq"
cp "$shim" "$tmp/shimdir/claude"
chmod +x "$tmp/shimdir/claude"

marker="$tmp/real-args.txt"
cat > "$tmp/bin/claude" <<SH
#!/usr/bin/env bash
printf '%s' "\$*" > "$marker"
echo "real-claude ran"
SH
chmod +x "$tmp/bin/claude"

# A pty is required: the shim only preseeds trust for interactive sessions
# ([ -t 0 ] && [ -t 1 ]). macOS `script` allocates one.
run_shim() { # cwd [args...]
  local dir="$1"; shift
  script -q /dev/null env -i HOME="$work" \
    PATH="$tmp/shimdir:$tmp/tools:$tmp/bin:/usr/bin:/bin" \
    TERM="$TERM" bash -c 'cd "$1" && shift && exec "$@"' \
    _ "$dir" "$tmp/shimdir/claude" "$@" | tr -d '\010\r' | sed '1s/^\^D//'
}

config="$work/.claude.json"

# 1) plain non-git folder: flags the cwd, passes args through ----------------
plain="$tmp/plain dir"
mkdir -p "$plain"
plain_real="$(cd "$plain" && pwd -P)"
out="$(run_shim "$plain" --model x 2>&1)"
check "plain: passthrough output" "real-claude ran" "$out"
check "plain: args reach real binary" "--model x" "$(cat "$marker")"
got="$(jq -r --arg p "$plain_real" '.projects[$p].hasTrustDialogAccepted' "$config")"
check "plain: cwd flagged true" "true" "$got"

# 2) idempotent: second run must not corrupt, keeps unrelated data ----------
printf '{"keep":42,"projects":{"%s":{"hasTrustDialogAccepted":true,"x":1}}}' "$plain" > "$config"
run_shim "$plain" >/dev/null 2>&1
check "idempotent: preserves sibling keys" "42" "$(jq -r '.keep' "$config")"
check "idempotent: preserves project keys" "1" "$(jq -r --arg p "$plain" '.projects[$p].x' "$config")"

# 3) git repo: flags the repo root, not the nested cwd -----------------------
# /var -> /private/var on macOS: trust keys use physical paths, matching git.
repo="$tmp/repo"
mkdir -p "$repo/sub/deep"
repo_real="$(cd "$repo" && pwd -P)"
git -C "$repo" init -q
git -C "$repo" config user.email t@t
git -C "$repo" config user.name t
echo x > "$repo/f"
git -C "$repo" add f && git -C "$repo" commit -qm init
run_shim "$repo/sub/deep" >/dev/null 2>&1
check "repo: root flagged" "true" "$(jq -r --arg p "$repo_real" '.projects[$p].hasTrustDialogAccepted' "$config")"
check "repo: cwd flagged too" "true" "$(jq -r --arg p "$(cd "$repo/sub/deep" && pwd -P)" '.projects[$p].hasTrustDialogAccepted' "$config")"

# 4) linked worktree: also flags the main checkout root ----------------------
git -C "$repo" worktree add -q "$tmp/wt" -b feature 2>/dev/null
wt_real="$(cd "$tmp/wt" && pwd -P)"
run_shim "$tmp/wt" >/dev/null 2>&1
check "worktree: worktree dir flagged" "true" "$(jq -r --arg p "$wt_real" '.projects[$p].hasTrustDialogAccepted' "$config")"
check "worktree: main checkout flagged" "true" "$(jq -r --arg p "$repo_real" '.projects[$p].hasTrustDialogAccepted' "$config")"

# 5) broken config must not stop the handoff --------------------------------
echo 'not json{' > "$config"
out="$(run_shim "$plain" 2>&1)"
check "broken config: claude still runs" "real-claude ran" "$out"

# 6) no real claude on PATH -> 127 ------------------------------------------
if out="$(env -i HOME="$work" PATH="$tmp/shimdir:$tmp/tools:/usr/bin:/bin" \
    "$tmp/shimdir/claude" 2>&1)"; then
  check "missing real binary exits non-zero" "exit127" "exit0"
else
  check "missing real binary exits 127" "127" "$?"
fi

# 7) python fallback path (no jq) seeds the same roots -----------------------
rm -f "$config"
mkdir -p "$tmp/pybin"
ln -sf "$(command -v python3)" "$tmp/pybin/python3"
pyp="$tmp/pyplain"
mkdir -p "$pyp"
pyp_real="$(cd "$pyp" && pwd -P)"
out="$(script -q /dev/null env -i HOME="$work" \
    PATH="$tmp/shimdir:$tmp/pybin:$tmp/bin:/usr/bin:/bin" TERM="$TERM" \
    bash -c 'cd "$1" && shift && exec "$@"' _ "$pyp" "$tmp/shimdir/claude" 2>&1 | tr -d '\010\r' | sed '1s/^\^D//')"
check "python fallback: passthrough works" "real-claude ran" "$out"
got="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["projects"][sys.argv[2]]["hasTrustDialogAccepted"])' "$config" "$pyp_real")"
check "python fallback: cwd flagged true" "True" "$got"

# 8) non-tty run (e.g. -p style) skips the write -----------------------------
rm -f "$config"
nt="$tmp/nontty"
mkdir -p "$nt"
echo anything | env -i HOME="$work" PATH="$tmp/shimdir:$tmp/tools:$tmp/bin:/usr/bin:/bin" \
  bash -c 'cd "$1" && "$2"' _ "$nt" "$tmp/shimdir/claude" >/dev/null 2>&1
if [ -e "$config" ]; then
  check "non-tty: no trust write" "absent" "$(jq -r --arg p "$nt" '.projects[$p].hasTrustDialogAccepted // "absent"' "$config")"
else
  check "non-tty: no trust write" "absent" "absent"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all claude-shim tests passed"
