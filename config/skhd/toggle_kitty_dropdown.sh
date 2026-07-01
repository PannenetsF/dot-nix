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
wrapper_log="${log_dir}/kitty-quick-access-wrapper.log"

{
	printf '[%s] triggered USER=%s HOME=%s PATH=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${user_name}" "${home_dir}" "${PATH}"

	kitten_bin=""
	if command -v kitten >/dev/null 2>&1; then
		kitten_bin="$(command -v kitten)"
	elif [[ -x /opt/homebrew/bin/kitten ]]; then
		kitten_bin="/opt/homebrew/bin/kitten"
	elif [[ -x /usr/local/bin/kitten ]]; then
		kitten_bin="/usr/local/bin/kitten"
	elif [[ -x /Applications/kitty.app/Contents/MacOS/kitten ]]; then
		kitten_bin="/Applications/kitty.app/Contents/MacOS/kitten"
	fi

	if [[ -n "${kitten_bin}" ]]; then
		printf '[%s] using %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${kitten_bin}"
		"${kitten_bin}" quick-access-terminal >>"${log_dir}/kitty-quick-access.log" 2>&1 &
		child_pid=$!
		printf '[%s] started quick access terminal pid=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${child_pid}"
		exit 0
	fi

	printf '[%s] kitten command not found\n' "$(date '+%Y-%m-%d %H:%M:%S')"
} >>"${wrapper_log}" 2>&1

osascript -e 'display notification "kitten command not found" with title "skhd" subtitle "Kitty quick access terminal"' >/dev/null 2>&1 || true
exit 127
