#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/brew/unquarantine-casks.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

Q=com.apple.quarantine

# Fake Caskroom tree:
#   fake-code/<v>/bin/fake-code   loose binary, must be cleared
#   fake-code/<v>/bin/helper      loose binary, must be cleared
#   fake-code/<v>/Fake.app        .app path in brew list, must be skipped
#   fake-code/.metadata/...       receipt, must be skipped even if tagged
#   linky/<v>/bin/linky -> target symlink artifact, target must be cleared
staging="${tmp}/Caskroom"
mkdir -p "${staging}/fake-code/1.0/bin" "${staging}/fake-code/1.0/Fake.app" \
         "${staging}/fake-code/.metadata/1.0" "${staging}/linky/2.0/bin"
printf 'x' >"${staging}/fake-code/1.0/bin/fake-code"
printf 'x' >"${staging}/fake-code/1.0/bin/helper"
printf 'x' >"${staging}/fake-code/1.0/Fake.app/contents"
printf 'x' >"${staging}/fake-code/.metadata/1.0/receipt.json"
printf 'x' >"${staging}/linky/2.0/bin/linky-target"
ln -s linky-target "${staging}/linky/2.0/bin/linky"

for f in \
  "${staging}/fake-code/1.0/bin/fake-code" \
  "${staging}/fake-code/1.0/bin/helper" \
  "${staging}/fake-code/1.0/Fake.app" \
  "${staging}/fake-code/.metadata/1.0/receipt.json" \
  "${staging}/linky/2.0/bin/linky-target"; do
  xattr -w "$Q" "0381;6acde5da;;uuid" "$f"
done

# Fake brew: `list --cask <token>` prints artifact paths like real Homebrew
# (loose files and .app root); unknown casks exit non-zero.
bin="${tmp}/bin"
mkdir -p "$bin"
cat >"${bin}/brew" <<SH
#!/usr/bin/env bash
# Invoked as: brew list --cask <token> -> token is \$3
case "\$3" in
  fake-code)
    printf '%s\n' \\
      '${staging}/fake-code/.metadata/1.0/receipt.json' \\
      '${staging}/fake-code/1.0/Fake.app' \\
      '${staging}/fake-code/1.0/bin/fake-code' \\
      '${staging}/fake-code/1.0/bin/helper'
    ;;
  linky)
    printf '%s\n' '${staging}/linky/2.0/bin/linky'
    ;;
  *)
    echo 'Error: Cask not installed' >&2
    exit 1
    ;;
esac
SH
chmod +x "${bin}/brew"

# Execute the script body with the hard-coded CASKS array replaced by the
# test's tokens, so the test never depends on real casks being installed.
run_with_casks() {
  BREW_BIN="${bin}/brew" bash -c '
    set -euo pipefail
    script_path="$1"; shift
    CASKS=("$@")
    src="$(sed "/^CASKS=(/,/^)$/d" "$script_path")"
    eval "$src"
  ' _ "$script" "$@"
}

out="$(run_with_casks fake-code linky not-installed 2>&1)"
echo "$out"

# Loose binaries must be cleared.
xattr -p "$Q" "${staging}/fake-code/1.0/bin/fake-code" 2>/dev/null \
  && { echo "fake-code binary still quarantined" >&2; exit 1; }
xattr -p "$Q" "${staging}/fake-code/1.0/bin/helper" 2>/dev/null \
  && { echo "helper binary still quarantined" >&2; exit 1; }

# The symlink target must be cleared through the listed symlink path.
xattr -p "$Q" "${staging}/linky/2.0/bin/linky-target" 2>/dev/null \
  && { echo "linky target still quarantined" >&2; exit 1; }

# .app and .metadata must be left untouched.
xattr -p "$Q" "${staging}/fake-code/1.0/Fake.app" >/dev/null 2>&1 \
  || { echo ".app should keep quarantine (TCC-protected, normal approval flow)" >&2; exit 1; }
xattr -p "$Q" "${staging}/fake-code/.metadata/1.0/receipt.json" >/dev/null 2>&1 \
  || { echo ".metadata should never be touched" >&2; exit 1; }

# Both cleared casks are reported; the absent one stays silent.
grep -q "from fake-code" <<<"$out" || { echo "expected fake-code report" >&2; exit 1; }
grep -q "from linky"    <<<"$out" || { echo "expected linky report" >&2; exit 1; }
grep -q "not-installed" <<<"$out" && { echo "absent cask must be silent" >&2; exit 1; }

# Idempotent second run: nothing reported as cleared.
out2="$(run_with_casks fake-code linky not-installed 2>&1)"
[[ -z "$out2" ]] || { echo "second run must be silent, got: $out2" >&2; exit 1; }

# Missing brew -> clean exit 0 with a skip message.
out3="$(BREW_BIN="${tmp}/nope/brew" bash "$script" 2>&1)" \
  || { echo "missing brew must not fail" >&2; exit 1; }
grep -q "skipping" <<<"$out3" || { echo "expected skip message, got: $out3" >&2; exit 1; }

# Non-macOS -> no-op, verified with a fake `uname` ahead of real /usr/bin.
xattr -w "$Q" "0381;abc" "${staging}/fake-code/1.0/bin/helper"
mkdir -p "${tmp}/fakeproc"
cat >"${tmp}/fakeproc/uname" <<'SH'
#!/usr/bin/env bash
[ "$1" = "-s" ] && echo Linux
SH
chmod +x "${tmp}/fakeproc/uname"
PATH="${tmp}/fakeproc:/usr/bin:/bin" BREW_BIN="${bin}/brew" bash "$script"
xattr -p "$Q" "${staging}/fake-code/1.0/bin/helper" >/dev/null 2>&1 \
  || { echo "Linux run must not clear anything" >&2; exit 1; }

echo "unquarantine casks test OK"
