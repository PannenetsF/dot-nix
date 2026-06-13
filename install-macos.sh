#! /bin/bash
set -e

FILE_LOCK="$HOME/pf-init-macos"

PIP_EXTRA=()
if [ -n "$PIP_POSTFIX" ]; then
  # Preserve the previous whitespace-split behavior for simple extra pip flags.
  # shellcheck disable=SC2206
  PIP_EXTRA=($PIP_POSTFIX)
fi

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
