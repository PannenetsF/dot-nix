#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

assignments="${tmp_dir}/assignments.json"
commands="${tmp_dir}/commands"
stub="${tmp_dir}/aerospace"

cat >"${assignments}" <<'EOF'
{
  "1": [2, "main"],
  "2": [2, "main"],
  "3": [2, "main"],
  "4": [1, "main"],
  "5": [1, "main"],
  "6": [1, "main"],
  "7": [4, "main"],
  "8": [4, "main"],
  "9": ["built-in", "main"],
  "10": ["built-in", "main"]
}
EOF

cat >"${stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${AEROSPACE_COMMAND_LOG}"
case "$*" in
  "list-workspaces --focused --format %{workspace}")
    printf '7\n'
    ;;
  "list-workspaces --all --format "*)
    printf '1\t2\tfalse\n4\t1\tfalse\n7\t4\ttrue\n9\t3\tfalse\n'
    ;;
esac
EOF
chmod +x "${stub}"

AEROSPACE_COMMAND_LOG="${commands}" python3 \
  "${repo_root}/config/aerospace/rehome-workspaces.py" \
  "${assignments}" "${stub}"

assert_command() {
	local expected="$1"
	if ! grep -Fxq "${expected}" "${commands}"; then
		echo "missing command: ${expected}" >&2
		cat "${commands}" >&2
		exit 1
	fi
}

assert_command "move-workspace-to-monitor --workspace 1 2 main"
assert_command "move-workspace-to-monitor --workspace 4 1 main"
assert_command "move-workspace-to-monitor --workspace 7 4 main"
assert_command "move-workspace-to-monitor --workspace 9 built-in main"
assert_command "workspace 1"
assert_command "workspace 4"
assert_command "workspace 9"

echo "aerospace workspace re-home tests passed"
