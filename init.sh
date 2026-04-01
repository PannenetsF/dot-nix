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
  [[ -n "${PF_http_proxy-}" ]] && export http_proxy="$PF_http_proxy"
  [[ -n "${PF_https_proxy-}" ]] && export https_proxy="$PF_https_proxy"
  [[ -n "${PF_no_proxy-}" ]] && export no_proxy="$PF_no_proxy"
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
  curl -fsSL https://install.determinate.systems/nix/tag/v3.17.2 | sh -s -- --no-confirm
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
  echo "substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org/" > "$HOME/.config/nix/nix.conf"

  local nix_hm_dir
  # Prefer using the repository that contains this script (common usage:
  # `git clone ... ~/.config/nix-hm && bash ~/.config/nix-hm/init.sh`).
  if [[ -f "$script_dir/flake.nix" ]]; then
    nix_hm_dir="$script_dir"
    if [[ -d "$nix_hm_dir/.git" ]]; then
      git -C "$nix_hm_dir" pull --rebase || true
    fi
  else
    nix_hm_dir="$HOME/.config/nix-hm"
    if [[ -d "$nix_hm_dir/.git" ]]; then
      git -C "$nix_hm_dir" pull --rebase || true
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

  # Early, user-friendly check for the common error:
  #   flake ... does not provide attribute 'homeConfigurations."$system".activationPackage'
  if ! grep -q "\"$system\"" "$nix_hm_dir/flake.nix"; then
    die "flake does not define homeConfigurations for '$system'. Please update $nix_hm_dir (git pull) to a version that includes darwin support."
  fi

  # home.nix uses builtins.getEnv("USER"/"HOME"). In flakes, this may require --impure.
  local user
  user="$(whoami)"

  set +e
  USER="$user" nix --extra-experimental-features "nix-command flakes" run nixpkgs#home-manager -- \
    --extra-experimental-features "nix-command flakes" \
    switch --flake "$nix_hm_dir/#${system}" --impure
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    USER="$user" nix --extra-experimental-features "nix-command flakes" run nixpkgs#home-manager -- \
      --extra-experimental-features "nix-command flakes" \
      switch --flake "$nix_hm_dir/#${system}"
  fi
}

main "$@"
