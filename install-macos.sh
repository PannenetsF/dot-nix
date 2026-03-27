#! /bin/bash
set -e

FILE_LOCK="$HOME/pf-init-macos"

PIP_EXTRA=""
[ -n "$PIP_POSTFIX" ] && PIP_EXTRA="$PIP_EXTRA $PIP_POSTFIX"
PIP_EXTRA="$PIP_EXTRA --break-system-packages"

if [ -f "$FILE_LOCK" ]; then
  echo "All py packages are installed yet."
else
  pwd
  env | grep PATH
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install ruff ty jedi-language-server pynvim $PIP_EXTRA
  else
    python3 -m pip install ruff ty jedi-language-server pynvim $PIP_EXTRA
  fi
  mkdir -p "$HOME/.config"
  git clone https://github.com/PannenetsF/dot-nvim.git "$HOME/.config/nvim"
  nvim --headless -c 'Lazy' -c 'qa'
  nvim --headless -c 'TSUpdateSync' -c 'qa'
  echo hello >> "$FILE_LOCK"
fi
