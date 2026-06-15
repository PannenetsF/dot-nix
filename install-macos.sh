#! /bin/bash
set -e

FILE_LOCK="$HOME/pf-init-macos"

PIP_EXTRA=()
if [ -n "$PIP_POSTFIX" ]; then
  # Preserve the previous whitespace-split behavior for simple extra pip flags.
  # shellcheck disable=SC2206
  PIP_EXTRA=($PIP_POSTFIX)
fi

sync_config_repo() {
  local name="$1"
  local repo_url="$2"
  local dest="$3"
  local status

  mkdir -p "$(dirname "$dest")"
  if [ ! -e "$dest" ]; then
    git clone "$repo_url" "$dest"
    return
  fi

  if [ ! -d "$dest/.git" ]; then
    echo "[install-macos.sh] WARNING: $name exists but is not a git repo, skipping pull: $dest" >&2
    return
  fi

  if ! git -C "$dest" diff --quiet || ! git -C "$dest" diff --cached --quiet; then
    echo "[install-macos.sh] WARNING: $name has local changes, skipping git pull: $dest" >&2
    return
  fi

  status="$(git -C "$dest" status --porcelain)"
  if [ -n "$status" ]; then
    echo "[install-macos.sh] WARNING: $name has untracked files, skipping git pull: $dest" >&2
    return
  fi

  git -C "$dest" pull --ff-only || echo "[install-macos.sh] WARNING: failed to pull $name: $dest" >&2
}

sync_config_repo "nvim config" "https://github.com/PannenetsF/dot-nvim.git" "$HOME/.config/nvim"

python_tools_available() {
  command -v ruff >/dev/null 2>&1 &&
    command -v ty >/dev/null 2>&1 &&
    command -v jedi-language-server >/dev/null 2>&1 &&
    python3 - <<'PY' >/dev/null 2>&1
import pynvim
PY
}

install_python_tools() {
  if python_tools_available; then
    echo "[install-macos.sh] Python/Nvim tools are already available from the profile."
    return
  fi

  if command -v pip3 >/dev/null 2>&1; then
    PIP_CMD=(pip3)
  else
    PIP_CMD=(python3 -m pip)
  fi

  if "${PIP_CMD[@]}" install --help 2>/dev/null | grep -q -- "--break-system-packages"; then
    PIP_EXTRA+=(--break-system-packages)
  fi

  "${PIP_CMD[@]}" install ruff ty jedi-language-server pynvim "${PIP_EXTRA[@]}"
}

if [ -f "$FILE_LOCK" ]; then
  echo "All py packages are installed yet."
else
  pwd
  env | grep PATH
  install_python_tools
  nvim --headless -c 'Lazy' -c 'qa'
  nvim --headless -c 'TSUpdateSync' -c 'qa'
  echo hello >> "$FILE_LOCK"
fi
