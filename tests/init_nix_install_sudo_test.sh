#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home"

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

cat >"$tmp/bin/launchctl" <<'SH'
#!/usr/bin/env bash
exit 1
SH

cat >"$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo ' >>"$NIX_INSTALL_STUB_LOG"
printf '%q ' "$@" >>"$NIX_INSTALL_STUB_LOG"
printf '\n' >>"$NIX_INSTALL_STUB_LOG"

if [[ "${1-}" == "-E" && "${2-}" == "sh" ]]; then
  shift
  export NIX_INSTALLER_RAN_VIA_SUDO=1
  "$@"
  exit $?
fi

exit 0
SH

cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
if [ "${NIX_INSTALLER_RAN_VIA_SUDO-}" != "1" ]; then
  echo "installer was not run through sudo" >&2
  exit 42
fi
mkdir -p "$HOME/.nix-profile/etc/profile.d" "$HOME/nix-bin"
cat >"$HOME/.nix-profile/etc/profile.d/nix.sh" <<'PROFILE'
export PATH="$HOME/nix-bin:$PATH"
PROFILE
cat >"$NIX_STUB_BIN/nix" <<'NIX'
#!/usr/bin/env bash
printf 'nix ' >>"$NIX_INSTALL_STUB_LOG"
printf '%q ' "$@" >>"$NIX_INSTALL_STUB_LOG"
printf '\n' >>"$NIX_INSTALL_STUB_LOG"
exit 0
NIX
chmod +x "$NIX_STUB_BIN/nix"
INSTALLER
SH

cat >"$tmp/bin/brew" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "shellenv" ]]; then
  exit 0
fi
printf 'brew ' >>"$NIX_INSTALL_STUB_LOG"
printf '%q ' "$@" >>"$NIX_INSTALL_STUB_LOG"
printf '\n' >>"$NIX_INSTALL_STUB_LOG"
exit 0
SH

chmod +x "$tmp/bin"/*

NIX_INSTALL_STUB_LOG="$tmp/install.log" \
NIX_STUB_BIN="$tmp/bin" \
NIX_HM_ETC_DIR="$tmp/etc" \
NIX_HM_NIX_DAEMON_PROFILE="$tmp/missing-nix-daemon.sh" \
NIX_HM_NIX_PROFILE="$tmp/home/.nix-profile/etc/profile.d/nix.sh" \
PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
HOME="$tmp/home" \
bash "$repo_root/init.sh" >/dev/null

log="$(cat "$tmp/install.log")"
if [[ "$log" != *"sudo -E sh -s -- install --no-confirm"* ]]; then
  echo "expected init.sh to run Determinate installer through sudo -E sh" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

if [[ "$log" != *"#darwin-rebuild"* ]]; then
  echo "expected init.sh to continue into nix-darwin activation after installing nix" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
