# Shared helpers for install-macos.sh and install-linux-server.sh.
#
# This file is meant to be sourced, not executed. The caller must set
# INSTALL_LOG_PREFIX before sourcing it, e.g.:
#
#   INSTALL_LOG_PREFIX="[install-macos.sh]"
#   script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=/dev/null
#   . "$script_dir/install-common.sh"
#
# The library is compatible with macOS /bin/bash (3.2) and deliberately does
# not toggle `set -e`: the Linux caller runs without it, while the macOS caller
# opts in itself.

: "${INSTALL_LOG_PREFIX:=[install-common.sh]}"

# Split PIP_POSTFIX on whitespace into the PIP_EXTRA array. Preserves the
# previous whitespace-split behavior for simple extra pip flags.
setup_pip_extra() {
  PIP_EXTRA=()
  if [ -n "$PIP_POSTFIX" ]; then
    # shellcheck disable=SC2206
    PIP_EXTRA=($PIP_POSTFIX)
  fi
}

# Clone a config repo on first run, otherwise fast-forward it only when the
# working tree is completely clean (no local changes, no staged changes, no
# untracked files). Any unsafe state skips the pull rather than risking user
# work.
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
    echo "$INSTALL_LOG_PREFIX WARNING: $name exists but is not a git repo, skipping pull: $dest" >&2
    return
  fi

  if ! git -C "$dest" diff --quiet || ! git -C "$dest" diff --cached --quiet; then
    echo "$INSTALL_LOG_PREFIX WARNING: $name has local changes, skipping git pull: $dest" >&2
    return
  fi

  status="$(git -C "$dest" status --porcelain)"
  if [ -n "$status" ]; then
    echo "$INSTALL_LOG_PREFIX WARNING: $name has untracked files, skipping git pull: $dest" >&2
    return
  fi

  git -C "$dest" pull --ff-only || echo "$INSTALL_LOG_PREFIX WARNING: failed to pull $name: $dest" >&2
}

python_tools_available() {
  command -v ruff >/dev/null 2>&1 &&
    command -v ty >/dev/null 2>&1 &&
    command -v jedi-language-server >/dev/null 2>&1 &&
    python3 - <<'PY' >/dev/null 2>&1
import pynvim
PY
}

# Install ruff/ty/jedi-language-server/pynvim via pip only when the active
# profile does not already provide them. Prefers pip3, falls back to
# `python3 -m pip`, and appends --break-system-packages only when the selected
# pip understands it. Uses the caller-visible PIP_EXTRA array (initialized by
# setup_pip_extra) for any extra flags such as index URL overrides.
install_python_tools() {
  if python_tools_available; then
    echo "$INSTALL_LOG_PREFIX Python/Nvim tools are already available from the profile."
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
