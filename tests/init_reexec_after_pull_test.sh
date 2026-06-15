#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

script_repo="$tmp/nix-hm"
mkdir -p "$tmp/bin" "$tmp/home/.nix-profile/etc/profile.d" "$script_repo/.git"
cp "$repo_root/init.sh" "$script_repo/init.sh"
printf '"aarch64-darwin"\n' >"$script_repo/flake.nix"
: >"$tmp/home/.nix-profile/etc/profile.d/nix.sh"

cat >"$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
printf 'git ' >>"$NIX_STUB_LOG"
printf '%q ' "$@" >>"$NIX_STUB_LOG"
printf '\n' >>"$NIX_STUB_LOG"

case "$*" in
  *" rev-parse HEAD"*)
    if [[ -e "$NIX_PULL_STATE" ]]; then
      printf 'new-head\n'
    else
      printf 'old-head\n'
    fi
    exit 0
    ;;
  *" diff --quiet"*|*" diff --cached --quiet"*)
    exit 0
    ;;
  *" status --porcelain"*)
    exit 0
    ;;
  *" pull --rebase"*)
    : >"$NIX_PULL_STATE"
    exit 0
    ;;
esac

exit 0
SH

cat >"$tmp/bin/nix" <<'SH'
#!/usr/bin/env bash
printf 'nix reexec=%s ' "${NIX_HM_REEXECED_AFTER_PULL-0}" >>"$NIX_STUB_LOG"
printf '%q ' "$@" >>"$NIX_STUB_LOG"
printf '\n' >>"$NIX_STUB_LOG"
exit 0
SH

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

cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod +x "$tmp/bin"/*

NIX_STUB_LOG="$tmp/nix.log" \
NIX_PULL_STATE="$tmp/pulled" \
NIX_HM_NIX_DAEMON_PROFILE="$tmp/missing/nix-daemon.sh" \
NIX_HM_NIX_DAEMON_PROFILE_DIR="$tmp/missing-daemon-profile" \
PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
HOME="$tmp/home" \
bash "$script_repo/init.sh" --home-manager >/dev/null

log="$(cat "$tmp/nix.log")"
if [[ "$log" != *"git -C $script_repo pull --rebase"* ]]; then
  echo "expected init.sh to pull the script repository" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
if [[ "$log" != *"nix reexec=1"* ]]; then
  echo "expected init.sh to re-exec after the script repository updates" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
if [[ "$log" != *"nixpkgs#home-manager"* ]]; then
  echo "expected original --home-manager argument to survive re-exec" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
