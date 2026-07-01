#!/usr/bin/env bash
set -euo pipefail

cache_dir="${HOME}/Library/Caches/dot-nix"
config_dir="${HOME}/.config/aerospace"
log_dir="${HOME}/Library/Logs/aerospace"
dirty_file="/tmp/aerospace-workspace-indicator-dirty"

binary="${cache_dir}/aerospace-workspace-indicator"
source_file="${config_dir}/workspace_indicator.swift"
log_file="${log_dir}/workspace-indicator.log"

mkdir -p "${cache_dir}" "${log_dir}"
: >"${dirty_file}"

if [[ -f "${source_file}" && -x /usr/bin/swiftc ]]; then
	if [[ ! -x "${binary}" || "${source_file}" -nt "${binary}" ]]; then
		tmp_binary="${binary}.$$"
		if /usr/bin/swiftc "${source_file}" -o "${tmp_binary}" >>"${log_file}" 2>&1; then
			mv "${tmp_binary}" "${binary}"
		else
			rm -f "${tmp_binary}"
		fi
	fi
fi

if [[ ! -x "${binary}" ]]; then
	echo "workspace indicator binary is missing" >>"${log_file}"
	exit 1
fi

pkill -x aerospace-workspace-indicator >/dev/null 2>&1 || true
exec "${binary}" "${dirty_file}"
