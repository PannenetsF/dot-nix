#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_stub_bin() {
  local bin_dir="$1"
  local create_nix="${2:-1}"

  cat >"${bin_dir}/uname" <<'SH'
#!/usr/bin/env bash
case "$1" in
  -s) printf '%s\n' "${TEST_UNAME_S}" ;;
  -m) printf '%s\n' "${TEST_UNAME_M}" ;;
  *) exit 1 ;;
esac
SH

  if [[ "$create_nix" == "1" ]]; then
    cat >"${bin_dir}/nix" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH
  fi

  cat >"${bin_dir}/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
if [[ "$1" == "installer" ]]; then
  cat >"${NIX_TEST_BIN_DIR}/nix" <<'NIX'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
NIX
  chmod +x "${NIX_TEST_BIN_DIR}/nix"
fi
exit 0
SH

  cat >"${bin_dir}/installer" <<'SH'
#!/usr/bin/env bash
printf 'installer ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
cat >"${NIX_TEST_BIN_DIR}/nix" <<'NIX'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
NIX
chmod +x "${NIX_TEST_BIN_DIR}/nix"
exit 0
SH

  cat >"${bin_dir}/launchctl" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "print" && "$2" == "system/org.nixos.nix-daemon" ]]; then
  exit 0
fi
printf 'launchctl ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH

  cat >"${bin_dir}/git" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *"status --porcelain"* ]]; then
  exit 0
fi
if [[ "$*" == *"diff --quiet"* ]]; then
  exit 0
fi
if [[ "$*" == *"pull --rebase"* ]]; then
  echo "Already up to date."
  exit 0
fi
exit 0
SH

  cat >"${bin_dir}/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == "-o" ]]; then
    j=$((i + 1))
    : >"${!j}"
    break
  fi
done
exit 0
SH

  cat >"${bin_dir}/apt-get" <<'SH'
#!/usr/bin/env bash
echo "apt-get should not be called by init.sh" >&2
exit 1
SH

  cat >"${bin_dir}/id" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  printf '%s\n' "${TEST_ID_U:-0}"
  exit 0
fi
if [[ "$1" == "-nG" ]]; then
  printf 'testuser nix-users\n'
  exit 0
fi
exit 1
SH

  cat >"${bin_dir}/getent" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "group" && "$2" == "nix-users" ]]; then
  printf 'nix-users:x:30000:testuser\n'
  exit 0
fi
exit 2
SH

  cat >"${bin_dir}/systemctl" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "list-unit-files" && "$2" == "nix-daemon.service" ]]; then
  exit 0
fi
printf 'systemctl ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH

  cat >"${bin_dir}/usermod" <<'SH'
#!/usr/bin/env bash
printf 'usermod ' >>"${NIX_STUB_LOG}"
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH

  cat >"${bin_dir}/whoami" <<'SH'
#!/usr/bin/env bash
printf 'testuser\n'
SH

  chmod +x "${bin_dir}"/*
}

make_brew_bootstrap_stub() {
  local path="$1"

  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'brew-bootstrap\n' >>"${NIX_STUB_LOG}"
SH
  chmod +x "$path"
}

run_init_for() {
  local os="$1"
  local arch="$2"
  local uid="${3:-0}"
  local create_zshenv="${4:-0}"
  local create_nix="${5:-1}"
  local profile_nix="${6:-0}"
  local tmp
  tmp="$(mktemp -d)"

  mkdir -p "${tmp}/bin" "${tmp}/etc" "${tmp}/home/.nix-profile/etc/profile.d" "${tmp}/profile-bin" "${tmp}/nix-daemon-profile"
  if [[ "$profile_nix" == "1" ]]; then
    cat >"${tmp}/profile-bin/nix" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${NIX_STUB_LOG}"
printf '\n' >>"${NIX_STUB_LOG}"
exit 0
SH
    chmod +x "${tmp}/profile-bin/nix"
    printf 'export PATH=%q:"$PATH"\n' "${tmp}/profile-bin" >"${tmp}/home/.nix-profile/etc/profile.d/nix.sh"
  else
    : >"${tmp}/home/.nix-profile/etc/profile.d/nix.sh"
  fi
  if [[ "$create_zshenv" == "1" ]]; then
    printf 'legacy zshenv\n' >"${tmp}/etc/zshenv"
  fi
  make_stub_bin "${tmp}/bin" "$create_nix"
  make_brew_bootstrap_stub "${tmp}/brew-bootstrap"

  TEST_UNAME_S="$os" \
  TEST_UNAME_M="$arch" \
  TEST_ID_U="$uid" \
  NIX_STUB_LOG="${tmp}/nix.log" \
  NIX_TEST_BIN_DIR="${tmp}/bin" \
  NIX_HM_BREW_BOOTSTRAP="${tmp}/brew-bootstrap" \
  NIX_HM_ETC_DIR="${tmp}/etc" \
  NIX_HM_NIX_DAEMON_PROFILE="${tmp}/missing/nix-daemon.sh" \
  NIX_HM_NIX_DAEMON_PROFILE_DIR="${tmp}/nix-daemon-profile" \
  PIP_INDEX_URL="https://pypi.example/simple" \
  PIP_TRUSTED_HOST="pypi.example" \
  PIP_POSTFIX="--timeout 60" \
  PATH="${tmp}/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  HOME="${tmp}/home" \
  bash "${repo_root}/init.sh" >/dev/null

  cat "${tmp}/nix.log"
  if [[ "$create_zshenv" == "1" ]]; then
    if [[ -e "${tmp}/etc/zshenv" || ! -e "${tmp}/etc/zshenv.before-nix-darwin" ]]; then
      echo "expected existing zshenv to be moved aside for nix-darwin" >&2
      find "${tmp}/etc" -maxdepth 1 -type f -print >&2
      exit 1
    fi
  fi
  rm -rf "${tmp}"
}

darwin_log="$(run_init_for Darwin arm64 501 1)"
darwin_bootstrap_log="$(run_init_for Darwin arm64 501 0 0)"
darwin_existing_profile_log="$(run_init_for Darwin arm64 501 0 0 1)"
darwin_sudo_env_line="$(printf '%s\n' "$darwin_log" | awk '/^sudo env / { print; exit }')"
darwin_root_home="$(printf '%s\n' "$darwin_sudo_env_line" | awk '{
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^HOME=/) {
      sub(/^HOME=/, "", $i)
      print $i
      exit
    }
  }
}')"
if [[ "$darwin_log" != *"sudo env"* ]]; then
  echo "expected Darwin init to run darwin-rebuild through sudo env" >&2
  echo "$darwin_log" >&2
  exit 1
fi
# darwin-rebuild issues the single sudo prompt itself; there must be no eager
# `sudo -v` pre-auth by default (it would be a second prompt on Macs where sudo
# does not cache credentials, e.g. timestamp_timeout=0 or Touch-ID-only).
if [[ "$darwin_log" == *"sudo -v"* ]]; then
  echo "did not expect an eager 'sudo -v' pre-auth on the default darwin path" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_bootstrap_log" != *"determinate-pkg/stable/Universal"* ]]; then
  echo "expected Darwin init without nix to download the Determinate pkg installer" >&2
  echo "$darwin_bootstrap_log" >&2
  exit 1
fi
if [[ "$darwin_bootstrap_log" != *"Determinate.pkg"* ]]; then
  echo "expected Darwin pkg installer path to end in Determinate.pkg" >&2
  echo "$darwin_bootstrap_log" >&2
  exit 1
fi
if [[ "$darwin_bootstrap_log" != *"sudo installer -pkg"* ]]; then
  echo "expected Darwin init without nix to install Determinate with the macOS pkg" >&2
  echo "$darwin_bootstrap_log" >&2
  exit 1
fi
if [[ "$darwin_existing_profile_log" == *"determinate-pkg/stable/Universal"* ]]; then
  echo "expected Darwin init to source an existing nix profile before reinstalling Nix" >&2
  echo "$darwin_existing_profile_log" >&2
  exit 1
fi
if [[ "$darwin_existing_profile_log" != *"#darwin-rebuild"* ]]; then
  echo "expected Darwin init with nix only in profile PATH to continue to darwin-rebuild" >&2
  echo "$darwin_existing_profile_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"brew-bootstrap"* ]]; then
  echo "expected Darwin init to bootstrap Homebrew before darwin-rebuild" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"NIX_HM_HOME="*"/home"* || "$darwin_log" != *"NIX_HM_USER=testuser"* || "$darwin_log" != *"SUDO_USER=testuser"* ]]; then
  echo "expected Darwin sudo env to preserve original home-manager HOME and USER" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_root_home" != "/var/root" ]]; then
  echo "expected Darwin sudo env to use root HOME for the root nix process" >&2
  echo "$darwin_log" >&2
  exit 1
fi
for pip_env in \
  "PIP_INDEX_URL=https://pypi.example/simple" \
  "PIP_TRUSTED_HOST=pypi.example"; do
  if [[ "$darwin_sudo_env_line" != *"$pip_env"* ]]; then
    echo "expected Darwin sudo env to preserve $pip_env for activation scripts" >&2
    echo "$darwin_log" >&2
    exit 1
  fi
done
if [[ "$darwin_sudo_env_line" != *"PIP_POSTFIX=--timeout"* || "$darwin_sudo_env_line" != *"60"* ]]; then
  echo "expected Darwin sudo env to preserve PIP_POSTFIX for activation scripts" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"#darwin-rebuild"* ]]; then
  echo "expected Darwin init to run the local darwin-rebuild app" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_sudo_env_line" != *" run --impure "*"#darwin-rebuild"* ]]; then
  echo "expected Darwin init to pass --impure to nix run while evaluating the app" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_sudo_env_line" != *" -- switch --flake "*" --impure"* ]]; then
  echo "expected Darwin init to pass --impure to darwin-rebuild switch so it can read NIX_HM_USER" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"#aarch64-darwin"* ]]; then
  echo "expected Darwin init to target aarch64-darwin" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" == *"Already up to date."* ]]; then
  echo "expected git pull stdout not to pollute the flake reference" >&2
  echo "$darwin_log" >&2
  exit 1
fi
if [[ "$darwin_log" != *"launchctl kickstart -k system/org.nixos.nix-daemon"* ]]; then
  echo "expected Darwin init to restart nix-daemon when managed nix cache config changes" >&2
  echo "$darwin_log" >&2
  exit 1
fi

linux_log="$(run_init_for Linux aarch64)"
if [[ "$linux_log" != *"nixpkgs#home-manager"* ]]; then
  echo "expected Linux init to keep using home-manager" >&2
  echo "$linux_log" >&2
  exit 1
fi
if [[ "$linux_log" != *"#aarch64-linux"* ]]; then
  echo "expected Linux init to target aarch64-linux" >&2
  echo "$linux_log" >&2
  exit 1
fi
if [[ "$linux_log" == *"apt-get"* ]]; then
  echo "expected Linux init not to manage apt packages" >&2
  echo "$linux_log" >&2
  exit 1
fi
if [[ "$linux_log" != *"systemctl restart nix-daemon"* ]]; then
  echo "expected Linux init to restart nix-daemon when managed nix cache config changes" >&2
  echo "$linux_log" >&2
  exit 1
fi
