#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/macos-home" "$tmp/linux-home"

cat >"$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1-}" == "clone" ]]; then
  dest="${@: -1}"
  mkdir -p "${dest:?missing destination}/.git"
fi
SH

cat >"$tmp/bin/python3" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
exit 0
SH

cat >"$tmp/bin/pip3" <<'SH'
#!/usr/bin/env bash
echo "pip3 should not run when Python tools are already in the profile" >&2
exit 1
SH

cat >"$tmp/bin/nvim" <<'SH'
#!/usr/bin/env bash
exit 0
SH

for tool in ruff ty jedi-language-server; do
  cat >"$tmp/bin/$tool" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done

chmod +x "$tmp/bin"/*

PATH="$tmp/bin:/usr/bin:/bin" \
HOME="$tmp/macos-home" \
bash "$repo_root/install-macos.sh" >/dev/null

PATH="$tmp/bin:/usr/bin:/bin" \
HOME="$tmp/linux-home" \
bash "$repo_root/install-linux-server.sh" >/dev/null
