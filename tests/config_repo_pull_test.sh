#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/home/.config/nvim/.git"
: >"$tmp/home/pf-init-macos"
: >"$tmp/home/pf-init"

cat >"$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${GIT_STUB_LOG}"
printf '\n' >>"${GIT_STUB_LOG}"
case "$*" in
  *" diff --quiet"*|*" diff --cached --quiet"*) exit 0 ;;
  *" status --porcelain"*) exit 0 ;;
  *" pull --ff-only"*) exit 0 ;;
esac
SH

cat >"$tmp/bin/nvim" <<'SH'
#!/usr/bin/env bash
echo "nvim should not run when the init lock already exists" >&2
exit 1
SH

cat >"$tmp/bin/pip3" <<'SH'
#!/usr/bin/env bash
echo "pip should not run when the init lock already exists" >&2
exit 1
SH

chmod +x "$tmp/bin"/*

GIT_STUB_LOG="$tmp/git-macos.log" \
PATH="$tmp/bin:/usr/bin:/bin" \
HOME="$tmp/home" \
PIP_POSTFIX="" \
bash "$repo_root/install-macos.sh" >/dev/null

if ! grep -Fq -- "-C $tmp/home/.config/nvim pull --ff-only" "$tmp/git-macos.log"; then
  echo "install-macos.sh should pull the nvim config repo even when the init lock exists" >&2
  cat "$tmp/git-macos.log" >&2
  exit 1
fi

GIT_STUB_LOG="$tmp/git-linux.log" \
PATH="$tmp/bin:/usr/bin:/bin" \
HOME="$tmp/home" \
PIP_POSTFIX="" \
bash "$repo_root/install-linux-server.sh" >/dev/null

if ! grep -Fq -- "-C $tmp/home/.config/nvim pull --ff-only" "$tmp/git-linux.log"; then
  echo "install-linux-server.sh should pull the nvim config repo even when the init lock exists" >&2
  cat "$tmp/git-linux.log" >&2
  exit 1
fi
