#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"${tmp}/brew" <<'SH'
#!/usr/bin/env bash
printf '%q ' "$@" >>"${BREW_STUB_LOG}"
printf '\n' >>"${BREW_STUB_LOG}"
SH
chmod +x "${tmp}/brew"

BREW_STUB_LOG="${tmp}/brew.log" \
BREW_BIN="${tmp}/brew" \
bash "${repo_root}/brew/install.sh"

brew_log="$(cat "${tmp}/brew.log")"

for expected in \
  "update --quiet" \
  "tap daipeihust/tap" \
  "tap gromgit/fuse" \
  "tap nikitabobko/tap" \
  "trust --formula daipeihust/tap/im-select" \
  "trust --formula gromgit/fuse/sshfs-mac" \
  "trust nikitabobko/tap"; do
  if [[ "$brew_log" != *"$expected"* ]]; then
    echo "expected brew/install.sh to run: $expected" >&2
    echo "$brew_log" >&2
    exit 1
  fi
done
