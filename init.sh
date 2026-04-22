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
  [[ -n "${PF_http_proxy-}" ]] && export http_proxy="$PF_http_proxy" || true
  [[ -n "${PF_https_proxy-}" ]] && export https_proxy="$PF_https_proxy" || true
  [[ -n "${PF_no_proxy-}" ]] && export no_proxy="$PF_no_proxy" || true
}

ensure_linux_prereqs() {
  # Ubuntu/Debian
  if command -v apt-get >/dev/null 2>&1; then
    if [[ "$(id -u)" -ne 0 ]]; then
      need_cmd sudo
      sudo -E apt-get update
      sudo -E apt-get install -y git curl
      # Optional, may not exist in minimal images.
      sudo -E apt-get install -y nscd || true
    else
      apt-get update
      apt-get install -y git curl
      apt-get install -y nscd || true
    fi
  else
    die "unsupported Linux distro: apt-get not found"
  fi
}

install_nix_if_needed() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi

  need_cmd curl
  ensure_proxy_env

  # Determinate Nix Installer (works on macOS + Linux, non-interactive)
  # Ref: https://install.determinate.systems/nix
  curl -fsSL https://install.determinate.systems/nix/tag/v3.17.2 | sh -s -- install --no-confirm
}

source_nix_profile() {
  # Multi-user (daemon) install
  if [[ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]]; then
    # shellcheck disable=SC1091
    . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    return 0
  fi

  # Single-user install
  if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    return 0
  fi

  die "nix profile script not found; nix may not be installed correctly"
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
  if [[ "$1" == "--upgrade" ]]; then
    do_upgrade=true
  fi

  if is_linux; then
    ensure_linux_prereqs
  elif is_darwin; then
    need_cmd git
    need_cmd curl
  else
    die "unsupported OS: $(uname -s)"
  fi

  install_nix_if_needed
  source_nix_profile
  need_cmd nix

  # Optional: keep old behavior behind an opt-in env to avoid weakening SSH security by default.
  if [[ "${NIX_HM_DISABLE_STRICT_SSH-}" == "1" ]]; then
    git config --global core.sshCommand 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
  fi

  mkdir -p "$HOME/.config/nix"
  echo "substituters = https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org/" > "$HOME/.config/nix/nix.conf"

  local nix_hm_dir
  # Prefer using the repository that contains this script (common usage:
  # `git clone ... ~/.config/nix-hm && bash ~/.config/nix-hm/init.sh`).
  # 安全地更新 git 仓库，处理本地更改
  safe_git_pull() {
    local dir="$1"
    if [[ ! -d "$dir/.git" ]]; then
      return
    fi
    # 检查是否有未暂存的更改
    if ! git -C "$dir" diff --quiet || ! git -C "$dir" diff --cached --quiet || [[ -n "$(git -C "$dir" status --porcelain | grep '^??')" ]]; then
      echo "[init.sh] WARNING: 本地有未提交的更改，跳过 git pull"
      echo "[init.sh] 建议: 提交更改或 git stash 后手动运行 git pull"
      return
    fi
    git -C "$dir" pull --rebase || true
  }

  if [[ -f "$script_dir/flake.nix" ]]; then
    nix_hm_dir="$script_dir"
    safe_git_pull "$nix_hm_dir"
  else
    nix_hm_dir="$HOME/.config/nix-hm"
    if [[ -d "$nix_hm_dir/.git" ]]; then
      safe_git_pull "$nix_hm_dir"
    else
      rm -rf "$nix_hm_dir"
      git clone https://github.com/PannenetsF/dot-nix.git "$nix_hm_dir"
    fi
  fi

  local system
  system="$(system_from_host)"

  if [[ ! -f "$nix_hm_dir/flake.nix" ]]; then
    die "flake.nix not found under $nix_hm_dir"
  fi

  # 如果是升级模式，先更新 flake 输入
  if [[ "$do_upgrade" == true ]]; then
    echo "[init.sh] 准备升级 flake 输入 (nixpkgs, home-manager 等)"
    read -p "[init.sh] 确认继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "[init.sh] 已取消升级"
      exit 0
    fi
    echo "[init.sh] 正在运行 nix flake update..."
    (cd "$nix_hm_dir" && nix --extra-experimental-features "nix-command flakes" flake update)
  fi

  # Early, user-friendly check for the common error:
  #   flake ... does not provide attribute 'homeConfigurations."$system".activationPackage'
  if ! grep -q "\"$system\"" "$nix_hm_dir/flake.nix"; then
    die "flake does not define homeConfigurations for '$system'. Please update $nix_hm_dir (git pull) to a version that includes darwin support."
  fi

  # home.nix uses builtins.getEnv("USER"/"HOME"). In flakes, this may require --impure.
  local user
  user="$(whoami)"

  if [[ "${DEBUG-}" == "1" ]]; then
    echo "[init.sh][debug] system=$system"
    echo "[init.sh][debug] nix_hm_dir=$nix_hm_dir"
    echo "[init.sh][debug] USER=$user"
    echo "[init.sh][debug] HOME=$HOME"
  fi

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

main "$@"
