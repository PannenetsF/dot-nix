#!/usr/bin/env bash
set -e

if [[ "${DEBUG-}" == "1" ]]; then
  set -x
fi

die() {
  echo "[init.sh] ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_darwin() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

ensure_proxy_env() {
  local proxy="${PF_proxy:-${PF_PROXY-}}"
  local http="${PF_http_proxy:-${PF_HTTP_PROXY:-${proxy}}}"
  local https="${PF_https_proxy:-${PF_HTTPS_PROXY:-${proxy}}}"
  local no="${PF_no_proxy:-${PF_NO_PROXY-}}"

  if [[ -n "$http" ]]; then
    export http_proxy="$http"
    export HTTP_PROXY="$http"
  fi

  if [[ -n "$https" ]]; then
    export https_proxy="$https"
    export HTTPS_PROXY="$https"
  fi

  if [[ -n "$no" ]]; then
    export no_proxy="$no"
    export NO_PROXY="$no"
  fi
}

ensure_linux_prereqs() {
  local user="$1"

  need_cmd git
  need_cmd curl
  ensure_linux_nix_user_group "$user"
}

ensure_linux_nix_user_group() {
  local user="$1"

  if ! getent group nix-users >/dev/null 2>&1; then
    return 0
  fi

  if id -nG "$user" | tr ' ' '\n' | grep -qx nix-users; then
    return 0
  fi

  echo "[init.sh] WARNING: user '$user' is not in nix-users; adding it may require a new login shell before Nix works reliably" >&2
  if [[ "$(id -u)" -eq 0 ]]; then
    usermod -aG nix-users "$user" || true
  elif command -v sudo >/dev/null 2>&1; then
    sudo usermod -aG nix-users "$user" || true
  fi
}

install_nix_if_needed() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi

  if maybe_source_nix_profile && command -v nix >/dev/null 2>&1; then
    return 0
  fi

  need_cmd curl
  ensure_proxy_env

  if is_darwin; then
    case "${NIX_HM_DARWIN_NIX_INSTALLER:-pkg}" in
      pkg)
        install_determinate_pkg_macos
        ;;
      cli)
        install_determinate_cli
        ;;
      *)
        die "unsupported NIX_HM_DARWIN_NIX_INSTALLER: ${NIX_HM_DARWIN_NIX_INSTALLER}"
        ;;
    esac
    return 0
  fi

  install_determinate_cli
}

install_determinate_cli() {
  # Determinate Nix Installer CLI path (works on macOS + Linux, non-interactive)
  # Ref: https://install.determinate.systems/nix
  if [[ "$(id -u)" -eq 0 ]]; then
    curl -fsSL https://install.determinate.systems/nix/tag/v3.17.2 | sh -s -- install --no-confirm
  else
    need_cmd sudo
    curl -fsSL https://install.determinate.systems/nix/tag/v3.17.2 | sudo -E sh -s -- install --no-confirm
  fi
}

install_determinate_pkg_macos() {
  local pkg
  local pkg_dir
  local pkg_url="${NIX_HM_DETERMINATE_PKG_URL:-https://install.determinate.systems/determinate-pkg/stable/Universal}"

  pkg_dir="$(mktemp -d)"
  pkg="${pkg_dir}/Determinate.pkg"
  curl -fsSL "$pkg_url" -o "$pkg"

  if [[ "$(id -u)" -ne 0 ]]; then
    need_cmd sudo
    sudo installer -pkg "$pkg" -target /
  else
    need_cmd installer
    installer -pkg "$pkg" -target /
  fi

  rm -rf "$pkg_dir"
}

maybe_source_nix_profile() {
  local daemon_profile="${NIX_HM_NIX_DAEMON_PROFILE:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
  # Multi-user (daemon) install
  if [[ -f "$daemon_profile" ]]; then
    # shellcheck disable=SC1091
    . "$daemon_profile"
    return 0
  fi

  # Single-user install
  if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    return 0
  fi

  return 1
}

source_nix_profile() {
  if maybe_source_nix_profile; then
    return 0
  fi

  die "nix profile script not found; nix may not be installed correctly"
}

managed_nix_conf_block() {
  local user="$1"
  local include_trust="$2"
  local substituters="${NIX_HM_SUBSTITUTERS:-https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org/}"
  local trusted_public_keys="${NIX_HM_TRUSTED_PUBLIC_KEYS:-cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=}"

  cat <<EOF
# BEGIN dot-nix managed cache config
extra-substituters = ${substituters}
extra-trusted-public-keys = ${trusted_public_keys}
EOF

  if [[ "$include_trust" == "1" ]]; then
    cat <<EOF
extra-trusted-substituters = ${substituters}
extra-trusted-users = ${user}
EOF
  fi

  cat <<'EOF'
# END dot-nix managed cache config
EOF
}

write_managed_nix_conf() {
  local target="$1"
  local block="$2"
  local dir
  local old_body
  local new_file
  dir="$(dirname "$target")"
  old_body="$(mktemp)"
  new_file="$(mktemp)"

  if [[ -f "$target" ]]; then
    awk '
      /^# BEGIN dot-nix managed cache config$/ { skip = 1; next }
      /^# END dot-nix managed cache config$/ { skip = 0; next }
      !skip { print }
    ' "$target" > "$old_body"
  fi

  {
    cat "$old_body"
    if [[ -s "$old_body" ]]; then
      printf '\n'
    fi
    printf '%s\n' "$block"
  } > "$new_file"

  if [[ -f "$target" ]] && cmp -s "$target" "$new_file"; then
    rm -f "$old_body" "$new_file"
    return 1
  fi

  if [[ -w "$target" || ( ! -e "$target" && -w "$dir" ) ]]; then
    mkdir -p "$dir"
    cp "$new_file" "$target"
  else
    need_cmd sudo
    sudo mkdir -p "$dir"
    sudo cp "$new_file" "$target"
    sudo chmod 0644 "$target"
  fi

  rm -f "$old_body" "$new_file"
  return 0
}

ensure_nix_conf_include() {
  local target="$1"
  local include_file="$2"
  local dir
  local old_body
  local new_file
  dir="$(dirname "$target")"
  old_body="$(mktemp)"
  new_file="$(mktemp)"

  if [[ -f "$target" ]]; then
    awk '
      /^# BEGIN dot-nix managed cache config$/ { skip = 1; next }
      /^# END dot-nix managed cache config$/ { skip = 0; next }
      $0 == "!include " include_file { found = 1 }
      !skip { print }
      END {
        if (!found) {
          if (NR > 0) print ""
          print "!include " include_file
        }
      }
    ' include_file="$include_file" "$target" > "$old_body"
  else
    printf '!include %s\n' "$include_file" > "$old_body"
  fi

  cp "$old_body" "$new_file"

  if [[ -f "$target" ]] && cmp -s "$target" "$new_file"; then
    rm -f "$old_body" "$new_file"
    return 1
  fi

  if [[ -w "$target" || ( ! -e "$target" && -w "$dir" ) ]]; then
    mkdir -p "$dir"
    cp "$new_file" "$target"
  else
    need_cmd sudo
    sudo mkdir -p "$dir"
    sudo cp "$new_file" "$target"
    sudo chmod 0644 "$target"
  fi

  rm -f "$old_body" "$new_file"
  return 0
}

restart_nix_daemon() {
  if is_darwin && command -v launchctl >/dev/null 2>&1; then
    if launchctl print system/org.nixos.nix-daemon >/dev/null 2>&1; then
      sudo launchctl kickstart -k system/org.nixos.nix-daemon || echo "[init.sh] WARNING: failed to restart org.nixos.nix-daemon; restart it manually for nix.conf changes to take effect" >&2
    fi
  elif is_linux && command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files nix-daemon.service >/dev/null 2>&1; then
      sudo systemctl restart nix-daemon || echo "[init.sh] WARNING: failed to restart nix-daemon; restart it manually for nix.conf changes to take effect" >&2
    fi
  fi
}

ensure_nix_cache_config() {
  local user="$1"
  local user_conf="$HOME/.config/nix/nix.conf"
  local daemon_conf="/etc/nix/nix.conf"
  local daemon_custom_conf="/etc/nix/nix.custom.conf"
  local daemon_profile_dir="${NIX_HM_NIX_DAEMON_PROFILE_DIR:-/nix/var/nix/profiles/default}"
  local user_block
  local daemon_block
  local daemon_changed=false

  mkdir -p "$(dirname "$user_conf")"
  user_block="$(managed_nix_conf_block "$user" 0)"
  write_managed_nix_conf "$user_conf" "$user_block" || true

  # Multi-user Nix ignores user-provided substituters unless the user is trusted
  # by the daemon or the substituter is trusted daemon-wide.
  if [[ -d "$daemon_profile_dir" ]]; then
    daemon_block="$(managed_nix_conf_block "$user" 1)"
    if write_managed_nix_conf "$daemon_custom_conf" "$daemon_block"; then
      daemon_changed=true
    fi
    if ensure_nix_conf_include "$daemon_conf" "nix.custom.conf"; then
      daemon_changed=true
    fi
    if [[ "$daemon_changed" == "true" ]]; then
      restart_nix_daemon
    fi
  fi
}

prepare_darwin_etc_for_nix_darwin() {
  local etc_dir="${NIX_HM_ETC_DIR:-/etc}"
  local zshenv="${etc_dir}/zshenv"
  local backup="${zshenv}.before-nix-darwin"

  if [[ ! -e "$zshenv" || -L "$zshenv" ]]; then
    return 0
  fi

  if [[ -e "$backup" ]]; then
    backup="${backup}.$(date +%Y%m%d%H%M%S)"
  fi

  echo "[init.sh] moving existing $zshenv to $backup before nix-darwin activation"
  if [[ -w "$zshenv" && -w "$etc_dir" ]]; then
    mv "$zshenv" "$backup"
  else
    need_cmd sudo
    sudo mv "$zshenv" "$backup"
  fi
}

prepare_nix_darwin_activation() {
  if ! is_darwin; then
    return 0
  fi

  prepare_darwin_etc_for_nix_darwin
}

append_env_if_set() {
  local name
  for name in "$@"; do
    if [[ -n "${!name-}" ]]; then
      env_args+=("${name}=${!name}")
    fi
  done
}

safe_git_pull() {
  local dir="$1"
  if ! command -v git >/dev/null 2>&1; then
    return
  fi
  if [[ ! -d "$dir/.git" ]]; then
    return
  fi
  # 检查是否有未暂存的更改
  if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet || [[ -n "$(git -C "$dir" status --porcelain | grep '^??')" ]]; then
    echo "[init.sh] WARNING: 本地有未提交的更改，跳过 git pull" >&2
    echo "[init.sh] 建议: 提交更改或 git stash 后手动运行 git pull" >&2
    return
  fi
  git -C "$dir" pull --rebase >&2 || true
}

early_pull_script_repo() {
  local script_dir="$1"
  if [[ -f "$script_dir/flake.nix" && -d "$script_dir/.git" ]] && command -v git >/dev/null 2>&1; then
    safe_git_pull "$script_dir"
    NIX_HM_EARLY_PULLED_DIR="$script_dir"
  fi
}

resolve_nix_hm_dir() {
  local script_dir="$1"
  local nix_hm_dir

  # Prefer using the repository that contains this script (common usage:
  # `git clone ... ~/.config/nix-hm && bash ~/.config/nix-hm/init.sh`).
  if [[ -f "$script_dir/flake.nix" ]]; then
    nix_hm_dir="$script_dir"
    if [[ "${NIX_HM_EARLY_PULLED_DIR-}" != "$nix_hm_dir" ]]; then
      safe_git_pull "$nix_hm_dir"
    fi
  else
    nix_hm_dir="$HOME/.config/nix-hm"
    if [[ -d "$nix_hm_dir/.git" ]]; then
      if [[ "${NIX_HM_EARLY_PULLED_DIR-}" != "$nix_hm_dir" ]]; then
        safe_git_pull "$nix_hm_dir"
      fi
    else
      rm -rf "$nix_hm_dir"
      git clone https://github.com/PannenetsF/dot-nix.git "$nix_hm_dir" >&2
    fi
  fi

  printf '%s\n' "$nix_hm_dir"
}

maybe_update_flake_inputs() {
  local nix_hm_dir="$1"

  echo "[init.sh] 准备升级 flake 输入 (nixpkgs, home-manager 等)"
  read -p "[init.sh] 确认继续？(y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "[init.sh] 已取消升级"
    exit 0
  fi
  echo "[init.sh] 正在运行 nix flake update..."
  (cd "$nix_hm_dir" && nix --extra-experimental-features "nix-command flakes" flake update)
}

assert_flake_has_system() {
  local nix_hm_dir="$1"
  local system="$2"

  if [[ ! -f "$nix_hm_dir/flake.nix" ]]; then
    die "flake.nix not found under $nix_hm_dir"
  fi

  # Early, user-friendly check for the common error:
  #   flake ... does not provide attribute 'homeConfigurations."$system".activationPackage'
  if ! grep -q "\"$system\"" "$nix_hm_dir/flake.nix"; then
    die "flake does not define homeConfigurations for '$system'. Please update $nix_hm_dir (git pull) to a version that includes darwin support."
  fi
}

darwin_env_args() {
  local user="$1"
  env_args=(
    "HOME=/var/root"
    "USER=root"
    "SUDO_USER=$user"
    "NIX_HM_HOME=$HOME"
    "NIX_HM_USER=$user"
    "NIX_HM_DEBUG=${DEBUG-}"
    "PATH=$PATH"
  )
  append_env_if_set \
    PIP_POSTFIX \
    PIP_INDEX_URL \
    PIP_EXTRA_INDEX_URL \
    PIP_TRUSTED_HOST \
    PIP_CONFIG_FILE \
    PIP_CERT \
    PIP_CLIENT_CERT \
    http_proxy \
    https_proxy \
    HTTP_PROXY \
    HTTPS_PROXY \
    no_proxy \
    NO_PROXY
}

activate_nix_darwin() {
  local nix_hm_dir="$1"
  local system="$2"
  local user="$3"

  prepare_nix_darwin_activation
  if [[ "$(id -u)" -ne 0 ]]; then
    need_cmd sudo
    local env_args
    darwin_env_args "$user"
    sudo env "${env_args[@]}" \
      nix --extra-experimental-features "nix-command flakes" run --impure "$nix_hm_dir#darwin-rebuild" -- \
      switch --flake "$nix_hm_dir/#${system}" --impure
  else
    NIX_HM_HOME="$HOME" NIX_HM_USER="$user" NIX_HM_DEBUG="${DEBUG-}" nix --extra-experimental-features "nix-command flakes" run --impure "$nix_hm_dir#darwin-rebuild" -- \
      switch --flake "$nix_hm_dir/#${system}" --impure
  fi
}

install_homebrew_if_needed() {
  local nix_hm_dir="$1"
  local bootstrap_script="${NIX_HM_BREW_BOOTSTRAP:-$nix_hm_dir/brew/install.sh}"

  if ! is_darwin; then
    return 0
  fi

  bash "$bootstrap_script"
}

activate_home_manager() {
  local nix_hm_dir="$1"
  local system="$2"
  local user="$3"

  set +e
  HOME="$HOME" USER="$user" NIX_HM_DEBUG="${DEBUG-}" nix --extra-experimental-features "nix-command flakes" run nixpkgs#home-manager -- \
    --extra-experimental-features "nix-command flakes" \
    switch -b backup --flake "$nix_hm_dir/#${system}" --impure
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    HOME="$HOME" USER="$user" NIX_HM_DEBUG="${DEBUG-}" nix --extra-experimental-features "nix-command flakes" run nixpkgs#home-manager -- \
      --extra-experimental-features "nix-command flakes" \
      switch -b backup --flake "$nix_hm_dir/#${system}"
  fi
}

restore_environment() {
  local nix_hm_dir="$1"
  local system="$2"
  local user="$3"
  local use_home_manager="$4"

  assert_flake_has_system "$nix_hm_dir" "$system"

  # flake.nix derives username/homeDirectory from USER/HOME, SUDO_USER, or
  # NIX_HM_*. Darwin activation keeps --impure on both nix run and
  # darwin-rebuild switch so nix-darwin can evaluate those values.
  if [[ "${DEBUG-}" == "1" ]]; then
    echo "[init.sh][debug] system=$system"
    echo "[init.sh][debug] nix_hm_dir=$nix_hm_dir"
    echo "[init.sh][debug] USER=$user"
    echo "[init.sh][debug] HOME=$HOME"
  fi

  if is_darwin && [[ "$use_home_manager" != true ]]; then
    install_homebrew_if_needed "$nix_hm_dir"
    activate_nix_darwin "$nix_hm_dir" "$system" "$user"
    return
  fi

  activate_home_manager "$nix_hm_dir" "$system" "$user"
}

system_from_host() {
  local arch
  local os
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux)
      case "$arch" in
        x86_64) echo "x86_64-linux" ;;
        aarch64|arm64) echo "aarch64-linux" ;;
        *) die "unsupported architecture on Linux: $arch" ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        x86_64) echo "x86_64-darwin" ;;
        arm64) echo "aarch64-darwin" ;;
        *) die "unsupported architecture on macOS: $arch" ;;
      esac
      ;;
    *)
      die "unsupported OS: $os"
      ;;
  esac
}

main() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  local do_upgrade=false
  local use_host=false
  local use_home_manager=false
  if [[ "${NIX_HM_PROFILE-}" == "host" ]]; then
    use_host=true
  fi
  if [[ "${NIX_HM_USE_HOME_MANAGER-}" == "1" ]]; then
    use_home_manager=true
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --upgrade)
        do_upgrade=true
        ;;
      --host)
        use_host=true
        ;;
      --home-manager)
        use_home_manager=true
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  ensure_proxy_env
  early_pull_script_repo "$script_dir"

  # 1. Install Nix when it is missing.
  install_nix_if_needed
  source_nix_profile
  need_cmd nix
  local user
  user="$(whoami)"

  # Keep host prerequisites narrow: command availability and Nix user group only.
  if is_linux; then
    ensure_linux_prereqs "$user"
  elif is_darwin; then
    need_cmd git
    need_cmd curl
  else
    die "unsupported OS: $(uname -s)"
  fi

  ensure_nix_cache_config "$user"

  # Optional: keep old behavior behind an opt-in env to avoid weakening SSH security by default.
  if [[ "${NIX_HM_DISABLE_STRICT_SSH-}" == "1" ]]; then
    git config --global core.sshCommand 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
  fi

  # 2. Use the repo containing this script, or clone nix-hm when curl-installed.
  local nix_hm_dir
  nix_hm_dir="$(resolve_nix_hm_dir "$script_dir")"

  local system
  system="$(system_from_host)"
  if [[ "$use_host" == true && "$system" == *-linux ]]; then
    system="${system}-host"
  fi

  if [[ "$do_upgrade" == true ]]; then
    maybe_update_flake_inputs "$nix_hm_dir"
  fi

  # 3. Restore the declarative environment through Nix.
  # 4. Python/nvim dependencies are handled by Home Manager activation scripts.
  restore_environment "$nix_hm_dir" "$system" "$user" "$use_home_manager"
}

main "$@"
