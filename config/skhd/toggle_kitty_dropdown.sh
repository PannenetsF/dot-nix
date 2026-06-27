#!/usr/bin/env bash
set -euo pipefail

user_name="${USER:-$(id -un)}"
home_dir="${HOME:-}"

if [[ -z "${home_dir}" && -n "${user_name}" ]]; then
	home_dir="$(dscl . -read "/Users/${user_name}" NFSHomeDirectory 2>/dev/null | awk '{ print $2 }' || true)"
fi

if [[ -z "${home_dir}" ]]; then
	home_dir="/Users/${user_name}"
fi

export HOME="${home_dir}"
export PATH="${home_dir}/.nix-profile/bin:/etc/profiles/per-user/${user_name}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:${PATH}}"

log_dir="${home_dir}/Library/Logs/skhd"
mkdir -p "${log_dir}" 2>/dev/null || true

if command -v kitten >/dev/null 2>&1; then
	exec kitten quick-access-terminal --detach --detached-log "${log_dir}/kitty-quick-access.log"
fi

if [[ -x /Applications/kitty.app/Contents/MacOS/kitten ]]; then
	exec /Applications/kitty.app/Contents/MacOS/kitten quick-access-terminal --detach --detached-log "${log_dir}/kitty-quick-access.log"
fi

osascript -e 'display notification "kitten command not found" with title "skhd" subtitle "Kitty quick access terminal"' >/dev/null 2>&1 || true
exit 127
