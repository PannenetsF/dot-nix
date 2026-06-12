#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home/.nix-profile/etc/profile.d" "$tmp/home/nix-bin"

cat >"$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) exit 1 ;;
esac
SH

cat >"$tmp/bin/id" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  printf '501\n'
  exit 0
fi
exit 1
SH

cat >"$tmp/bin/whoami" <<'SH'
#!/usr/bin/env bash
printf 'testuser\n'
SH

cat >"$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"status --porcelain"* ]]; then
  exit 0
fi
if [[ "$*" == *"diff --quiet"* ]]; then
  exit 0
fi
if [[ "$*" == *"pull --rebase"* ]]; then
  exit 0
fi
exit 0
SH

cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
echo "curl installer should not be called when an existing Nix profile script is present" >&2
exit 99
SH

cat >"$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo ' >>"$NIX_PROFILE_STUB_LOG"
printf '%q ' "$@" >>"$NIX_PROFILE_STUB_LOG"
printf '\n' >>"$NIX_PROFILE_STUB_LOG"
exit 0
SH

cat >"$tmp/bin/launchctl" <<'SH'
#!/usr/bin/env bash
exit 1
SH

cat >"$tmp/home/.nix-profile/etc/profile.d/nix.sh" <<'SH'
export PATH="$HOME/nix-bin:$PATH"
SH

cat >"$tmp/home/nix-bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix ' >>"$NIX_PROFILE_STUB_LOG"
printf '%q ' "$@" >>"$NIX_PROFILE_STUB_LOG"
printf '\n' >>"$NIX_PROFILE_STUB_LOG"
exit 0
SH

chmod +x "$tmp/bin"/* "$tmp/home/nix-bin/nix"

NIX_PROFILE_STUB_LOG="$tmp/init.log" \
NIX_HM_ETC_DIR="$tmp/etc" \
NIX_HM_NIX_DAEMON_PROFILE="$tmp/missing-nix-daemon.sh" \
NIX_HM_NIX_PROFILE="$tmp/home/.nix-profile/etc/profile.d/nix.sh" \
PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
HOME="$tmp/home" \
bash "$repo_root/init.sh" >/dev/null

log="$(cat "$tmp/init.log")"
if [[ "$log" != *"#darwin-rebuild"* ]]; then
  echo "expected init.sh to source the existing Nix profile and continue activation" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
