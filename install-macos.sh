#! /bin/bash
set -e

INSTALL_LOG_PREFIX="[install-macos.sh]"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$script_dir/install-common.sh"

FILE_LOCK="$HOME/pf-init-macos"

setup_pip_extra

sync_config_repo "nvim config" "https://github.com/PannenetsF/dot-nvim.git" "$HOME/.config/nvim"

if [ -f "$FILE_LOCK" ]; then
  echo "[install-macos.sh] lock file present, skipping python tools bootstrap: $FILE_LOCK"
else
  install_python_tools
  nvim --headless -c 'Lazy' -c 'qa'
  nvim --headless -c 'TSUpdateSync' -c 'qa'
  touch "$FILE_LOCK"
fi
