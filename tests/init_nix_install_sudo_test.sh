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
  printf 'git ' >>"$NIX_INSTALL_STUB_LOG"
  printf '%q ' "$@" >>"$NIX_INSTALL_STUB_LOG"
  printf '\n' >>"$NIX_INSTALL_STUB_LOG"
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
printf 'curl ' >>"$NIX_INSTALL_STUB_LOG"
printf '%q ' "$@" >>"$NIX_INSTALL_STUB_LOG"
printf '\n' >>"$NIX_INSTALL_STUB_LOG"
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

chmod +x "$tmp/bin"/*

cat >"$tmp/brew-bootstrap" <<'SH'
#!/usr/bin/env bash
printf 'brew-bootstrap\n' >>"$NIX_INSTALL_STUB_LOG"
SH
chmod +x "$tmp/brew-bootstrap"

NIX_INSTALL_STUB_LOG="$tmp/install.log" \
NIX_STUB_BIN="$tmp/bin" \
NIX_HM_BREW_BOOTSTRAP="$tmp/brew-bootstrap" \
NIX_HM_ETC_DIR="$tmp/etc" \
NIX_HM_DARWIN_NIX_INSTALLER=cli \
PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
HOME="$tmp/home" \
bash "$repo_root/init.sh" >/dev/null

log="$(cat "$tmp/install.log")"
git_pull_line="$(grep -n "git .* pull --rebase" "$tmp/install.log" | head -n 1 | cut -d: -f1)"
curl_line="$(grep -n "^curl " "$tmp/install.log" | head -n 1 | cut -d: -f1)"
if [[ -z "$git_pull_line" || -z "$curl_line" || "$git_pull_line" -ge "$curl_line" ]]; then
  echo "expected init.sh to git pull the config repo before installing nix" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

if [[ "$log" != *"sudo -E sh -s -- install --no-confirm"* ]]; then
  echo "expected init.sh to run Determinate installer through sudo -E sh" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

sudo_validate_line="$(grep -n "^sudo -v " "$tmp/install.log" | head -n 1 | cut -d: -f1)"
sudo_install_line="$(grep -n "sudo -E sh -s -- install --no-confirm" "$tmp/install.log" | head -n 1 | cut -d: -f1)"
if [[ -z "$sudo_validate_line" || -z "$sudo_install_line" || "$sudo_validate_line" -ge "$sudo_install_line" ]]; then
  echo "expected init.sh to validate sudo before running the Determinate installer" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

if [[ "$log" != *"#darwin-rebuild"* ]]; then
  echo "expected init.sh to continue into nix-darwin activation after installing nix" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
