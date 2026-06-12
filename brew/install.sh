#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${SCRIPT_DIR}/Brewfile"

default_brew_bin() {
  if [[ -n "${NIX_HM_BREW_BIN-}" ]]; then
    printf '%s\n' "$NIX_HM_BREW_BIN"
    return
  fi

  case "$(uname -m)" in
    arm64) printf '/opt/homebrew/bin/brew\n' ;;
    *) printf '/usr/local/bin/brew\n' ;;
  esac
}

load_brew_shellenv() {
  local brew_bin="$1"
  if [[ -x "$brew_bin" ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi
  return 1
}

if ! command -v brew >/dev/null 2>&1; then
  if ! load_brew_shellenv "$(default_brew_bin)"; then
    if [[ "$(id -u)" -eq 0 ]]; then
      echo "Homebrew must be installed as the target user, not root." >&2
      exit 1
    fi
    command -v curl >/dev/null 2>&1 || {
      echo "curl is required to install Homebrew." >&2
      exit 1
    }
    if [[ "$(uname -s)" == "Darwin" ]]; then
      if [[ -t 0 ]]; then
        sudo -v
      else
        sudo -n -v || {
          echo "Homebrew install needs an existing sudo session when running without a TTY." >&2
          exit 1
        }
      fi
    fi
    echo "Homebrew is not installed; installing it non-interactively."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew_shellenv "$(default_brew_bin)" || {
      echo "Homebrew installed but brew is still not available on PATH." >&2
      exit 1
    }
  fi
fi

brew trust --formula daipeihust/tap/im-select || true
brew trust --formula gromgit/fuse/sshfs-mac || true
brew trust whatpulse/whatpulse || true

brew bundle --no-upgrade --file="${BREWFILE}"
