#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/state"
export WM_TEST_LOG="$tmp/log" WM_TEST_STATE="$tmp/state"

cat >"$tmp/bin/id" <<'SH'
#!/usr/bin/env bash
echo 501
SH
cat >"$tmp/bin/launchctl" <<'SH'
#!/usr/bin/env bash
echo "launchctl $*" >> "$WM_TEST_LOG"
exit 1 # Missing/unloaded agents are safe and do not prevent process cleanup.
SH
cat >"$tmp/bin/pgrep" <<'SH'
#!/usr/bin/env bash
[[ "$1 $2 $3" == "-u 501 -x" ]] || exit 9
[[ -e "$WM_TEST_STATE/$4" ]]
SH
cat >"$tmp/bin/pkill" <<'SH'
#!/usr/bin/env bash
echo "pkill $*" >> "$WM_TEST_LOG"
[[ "$1 $2 $3 $4" == "-TERM -u 501 -x" ]] || exit 9
if [[ "${WM_TEST_STUBBORN:-0}" != 1 ]]; then
  rm -f "$WM_TEST_STATE/$5"
fi
SH
cat >"$tmp/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/bin/"*

run_cleanup() {
  PATH="$tmp/bin:$PATH" /bin/bash "$repo_root/config/omniwm/stop-aerospace.sh"
}

# All desktop commands are stubs; never unload a real LaunchAgent in tests.
run_cleanup
[[ "$(wc -l <"$WM_TEST_LOG" | tr -d ' ')" == 3 ]]
grep -Fxq 'launchctl bootout gui/501/org.nix-community.home.aerospace' "$WM_TEST_LOG"
grep -Fxq 'launchctl bootout gui/501/org.nix-community.home.aerospace-workspace-indicator' "$WM_TEST_LOG"
grep -Fxq 'launchctl bootout gui/501/org.nix-community.home.borders' "$WM_TEST_LOG"

touch "$WM_TEST_STATE/AeroSpace" "$WM_TEST_STATE/borders"
run_cleanup
grep -Fxq 'pkill -TERM -u 501 -x AeroSpace' "$WM_TEST_LOG"
grep -Fxq 'pkill -TERM -u 501 -x borders' "$WM_TEST_LOG"
[[ ! -e "$WM_TEST_STATE/AeroSpace" && ! -e "$WM_TEST_STATE/borders" ]]
# A second run is harmless.
run_cleanup

touch "$WM_TEST_STATE/AeroSpace"
if WM_TEST_STUBBORN=1 run_cleanup >"$tmp/error" 2>&1; then
  echo 'expected cleanup to refuse a WM that would not quit' >&2
  exit 1
fi
grep -Fq 'AeroSpace is still running' "$tmp/error"
if grep -Eq 'KILL|OmniWM|open ' "$WM_TEST_LOG"; then
  echo 'cleanup must not force-kill processes or launch OmniWM' >&2
  exit 1
fi
echo 'OmniWM trial stubbed cleanup checks passed'
