#! /bin/bash
set -e

FILE_LOCK="$HOME/pf-init-macos"
KITTY_CONFIG_REPO="${KITTY_CONFIG_REPO:-https://github.com/PannenetsF/dot-kitty.git}"
KITTY_CONFIG_BRANCH="${KITTY_CONFIG_BRANCH:-main}"

git_network() {
  git \
    -c "http.lowSpeedLimit=${GIT_LOW_SPEED_LIMIT:-1}" \
    -c "http.lowSpeedTime=${GIT_LOW_SPEED_TIME:-20}" \
    "$@"
}

sync_git_config() {
  local repo="$1"
  local branch="$2"
  local dest="$3"

  mkdir -p "$(dirname "$dest")"
  if [ -d "$dest/.git" ]; then
    if ! git_network -C "$dest" fetch origin "$branch"; then
      echo "warn: failed to fetch $repo; keeping existing $dest" >&2
      return 0
    fi
    git -C "$dest" checkout -B "$branch" "origin/$branch"
    git -C "$dest" reset --hard "origin/$branch"
    git -C "$dest" clean -fd
  else
    rm -rf "$dest"
    if ! git_network clone --branch "$branch" "$repo" "$dest"; then
      echo "warn: failed to clone $repo; continuing without $dest" >&2
      mkdir -p "$dest"
    fi
  fi
}

PIP_EXTRA=()
if [ -n "$PIP_POSTFIX" ]; then
  # Preserve the previous whitespace-split behavior for simple extra pip flags.
  # shellcheck disable=SC2206
  PIP_EXTRA=($PIP_POSTFIX)
fi

sync_git_config "$KITTY_CONFIG_REPO" "$KITTY_CONFIG_BRANCH" "$HOME/.config/kitty"

if [ -f "$FILE_LOCK" ]; then
  echo "All py packages are installed yet."
else
  pwd
  env | grep PATH
  if command -v pip3 >/dev/null 2>&1; then
    PIP_CMD=(pip3)
  else
    PIP_CMD=(python3 -m pip)
  fi

  if "${PIP_CMD[@]}" install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
    PIP_EXTRA+=(--break-system-packages)
  fi

  "${PIP_CMD[@]}" install ruff ty jedi-language-server pynvim "${PIP_EXTRA[@]}"
  mkdir -p "$HOME/.config"
  if [ ! -d "$HOME/.config/nvim" ]; then
    git clone https://github.com/PannenetsF/dot-nvim.git "$HOME/.config/nvim"
  fi
  nvim --headless -c 'Lazy' -c 'qa'
  nvim --headless -c 'TSUpdateSync' -c 'qa'
  echo hello >> "$FILE_LOCK"
fi
