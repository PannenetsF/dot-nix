#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home"

cat >"$tmp/bin/pip3" <<'SH'
#!/usr/bin/env bash
if [[ "${1-}" == "install" && "${2-}" == "--help" ]]; then
  printf 'Usage: pip3 install [options]\n'
  exit 0
fi
for arg in "$@"; do
  if [[ "$arg" == "--break-system-packages" ]]; then
    echo "no such option: --break-system-packages" >&2
    exit 2
  fi
done
printf '%q ' "$@" >"${PIP_STUB_LOG}"
printf '\n' >>"${PIP_STUB_LOG}"
SH

cat >"$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1-}" == "clone" ]]; then
  mkdir -p "${3:?missing destination}"
fi
SH

cat >"$tmp/bin/nvim" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod +x "$tmp/bin"/*

PIP_STUB_LOG="$tmp/pip.log" \
PATH="$tmp/bin:/usr/bin:/bin" \
HOME="$tmp/home" \
bash "$repo_root/install-macos.sh" >/dev/null

if grep -q -- "--break-system-packages" "$tmp/pip.log"; then
  echo "install-macos.sh should not pass unsupported --break-system-packages to pip3" >&2
  cat "$tmp/pip.log" >&2
  exit 1
fi
