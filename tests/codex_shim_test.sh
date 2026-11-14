#!/usr/bin/env bash
# Stubbed tests for the Codex directory-trust shim. Uses a temporary CODEX_HOME
# and a fake real binary; never touches the user's Codex configuration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shim="${repo_root}/config/codex/codex-shim.sh"

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
work="$tmp/home"
codex_home="$work/codex-home"
mkdir -p "$work" "$codex_home" "$tmp/bin" "$tmp/shimdir" "$tmp/pybin"
ln -s "$(command -v python3)" "$tmp/pybin/python3"
cp "$shim" "$tmp/shimdir/codex"
chmod +x "$tmp/shimdir/codex"
test_path="$tmp/shimdir:$tmp/pybin:$tmp/bin:/usr/bin:/bin"

marker="$tmp/real-args.txt"
cat > "$tmp/bin/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_TEST_MARKER"
echo "real-codex ran"
SH
chmod +x "$tmp/bin/codex"

# Allocate a pty because interactive-only preseeding is intentional. macOS and
# util-linux script have different argv forms and echo different banners; the
# assertions use the marker file and whether the expected text is present.
run_shim() { # cwd [args...]
  local dir="$1"; shift
  local envs=(env -i HOME="$work" CODEX_HOME="$codex_home" CODEX_TEST_MARKER="$marker"
    PATH="$test_path" TERM="${TERM:-xterm}")
  if [ "$(uname -s)" = Darwin ]; then
    script -q /dev/null "${envs[@]}" \
      bash -c 'cd "$1" && shift && exec "$@"' _ "$dir" "$tmp/shimdir/codex" "$@" \
      | tr -d '\010\r'
  else
    local command quoted
    printf -v command 'cd %q && exec ' "$dir"
    printf -v quoted '%q ' "${envs[@]}" "$tmp/shimdir/codex" "$@"
    script -qec "$command$quoted" /dev/null | tr -d '\010\r'
  fi
}

config="$codex_home/config.toml"
trusted() { # path
  python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["projects"][sys.argv[2]]["trust_level"])' "$config" "$1" 2>/dev/null || echo absent
}

# 1) plain non-git folder: trust cwd and preserve exact argument boundaries.
plain="$tmp/plain dir"
mkdir -p "$plain"
plain_real="$(cd "$plain" && pwd -P)"
out="$(run_shim "$plain" --model 'two words')"
case "$out" in *"real-codex ran"*) ;; *) out="" ;; esac
[ -n "$out" ] || failures=$((failures + 1))
check "plain: args reach real binary" $'--model\ntwo words' "$(cat "$marker")"
check "plain: cwd trusted" trusted "$(trusted "$plain_real")"

# 2) idempotence: preserve comments, other tables, keys, and explicit distrust.
repo="$tmp/repo"
mkdir -p "$repo/sub/deep"
repo_real="$(cd "$repo" && pwd -P)"
git -C "$repo" init -q
git -C "$repo" config user.email t@t
git -C "$repo" config user.name t
echo x > "$repo/f"
git -C "$repo" add f && git -C "$repo" commit -qm init
cat > "$config" <<EOF
# keep this comment
[features]
hooks = true

[projects."$plain_real"]
trust_level = "trusted"
custom = 42

[projects."$repo_real"]
trust_level = "untrusted"
EOF
run_shim "$repo/sub/deep" >/dev/null
check "idempotent: comment survives" 1 "$(grep -c '^# keep this comment$' "$config")"
check "idempotent: unrelated table survives" True "$(python3 -I -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["features"]["hooks"])' "$config")"
check "idempotent: existing project keys survive" 42 "$(python3 -I -c 'import sys,tomllib;print(tomllib.load(open(sys.argv[1],"rb"))["projects"][sys.argv[2]]["custom"])' "$config" "$plain_real")"
check "idempotent: explicit distrust is not overwritten" untrusted "$(trusted "$repo_real")"
check "repo: nested cwd trusted" trusted "$(trusted "$(cd "$repo/sub/deep" && pwd -P)")"

# 3) linked worktree: seed both worktree and main checkout.
git -C "$repo" worktree add -q "$tmp/wt" -b feature 2>/dev/null
wt_real="$(cd "$tmp/wt" && pwd -P)"
printf '[features]\nhooks = true\n' > "$config"
run_shim "$tmp/wt" >/dev/null
check "worktree: worktree trusted" trusted "$(trusted "$wt_real")"
check "worktree: main checkout trusted" trusted "$(trusted "$repo_real")"

# 4) existing mode is preserved; a new config is private.
check "new config: mode 600" 600 "$(python3 -I -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$config")"
chmod 640 "$config"
run_shim "$plain" >/dev/null
check "existing config: mode preserved" 640 "$(python3 -I -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$config")"

# 5) concurrent fresh launches share one config without losing project entries.
rm -f "$config"
pids=()
for n in 1 2 3 4; do
  dir="$tmp/concurrent-$n"
  mkdir -p "$dir"
  run_shim "$dir" > "$tmp/concurrent-$n.log" 2>&1 &
  pids+=("$!")
done
concurrent_status=0
for pid in "${pids[@]}"; do
  wait "$pid" || concurrent_status=1
done
check "concurrent: every real codex ran" 0 "$concurrent_status"
for n in 1 2 3 4; do
  check "concurrent: project $n survives" trusted "$(trusted "$(cd "$tmp/concurrent-$n" && pwd -P)")"
done

# 6) malformed config is not replaced and never prevents the handoff.
printf 'not valid toml{' > "$config"
before="$(cat "$config")"
out="$(run_shim "$plain" 2>&1)"
case "$out" in *"real-codex ran"*) result=ran ;; *) result=blocked ;; esac
check "broken config: codex still runs" ran "$result"
check "broken config: bytes untouched" "$before" "$(cat "$config")"

# 7) non-interactive invocation does not write trust.
rm -f "$config"
nt="$tmp/nontty"
mkdir -p "$nt"
printf anything | env -i HOME="$work" CODEX_HOME="$codex_home" CODEX_TEST_MARKER="$marker" \
  PATH="$test_path" \
  bash -c 'cd "$1" && "$2"' _ "$nt" "$tmp/shimdir/codex" >/dev/null 2>&1
check "non-tty: no trust write" absent "$(trusted "$(cd "$nt" && pwd -P)")"

# 8) no real codex on PATH is a visible 127.
if env -i HOME="$work" PATH="$tmp/shimdir:/usr/bin:/bin" \
    "$tmp/shimdir/codex" >/dev/null 2>&1; then
  result=0
else
  result=$?
fi
check "missing real binary exits 127" 127 "$result"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all codex-shim tests passed"
