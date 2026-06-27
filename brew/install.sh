#!/usr/bin/env bash
set -euo pipefail

BREW_BIN="${BREW_BIN:-}"

if [[ -z "$BREW_BIN" ]]; then
  if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN="/usr/local/bin/brew"
  fi
fi

if [[ -z "$BREW_BIN" ]]; then
  echo "Installing Homebrew..." >&2
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN="/usr/local/bin/brew"
  else
    echo "Homebrew installation finished, but brew was not found." >&2
    exit 1
  fi
fi

"$BREW_BIN" update --quiet || true
"$BREW_BIN" tap daipeihust/tap || true
"$BREW_BIN" tap gromgit/fuse || true
"$BREW_BIN" tap nikitabobko/tap || true
"$BREW_BIN" trust --formula daipeihust/tap/im-select || true
"$BREW_BIN" trust --formula gromgit/fuse/sshfs-mac || true
"$BREW_BIN" trust nikitabobko/tap || true
