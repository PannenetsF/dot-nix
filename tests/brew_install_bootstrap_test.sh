#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/homebrew/bin"

cat >"$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf 'homebrew-installer NONINTERACTIVE=%s\n' "${NONINTERACTIVE-}" >>"$BREW_TEST_LOG"
cat >"$BREW_TEST_PREFIX/bin/brew" <<'BREW'
#!/usr/bin/env bash
if [[ "$1" == "shellenv" ]]; then
  printf 'export PATH="%s/bin:$PATH"\n' "$BREW_TEST_PREFIX"
  exit 0
fi
printf 'brew ' >>"$BREW_TEST_LOG"
printf '%q ' "$@" >>"$BREW_TEST_LOG"
printf '\n' >>"$BREW_TEST_LOG"
exit 0
BREW
chmod +x "$BREW_TEST_PREFIX/bin/brew"
INSTALLER
SH

cat >"$tmp/bin/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo ' >>"$BREW_TEST_LOG"
printf '%q ' "$@" >>"$BREW_TEST_LOG"
printf '\n' >>"$BREW_TEST_LOG"
exit 0
SH

cat >"$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-s" ]]; then
  printf 'Darwin\n'
  exit 0
fi
exit 1
SH

chmod +x "$tmp/bin"/*

BREW_TEST_LOG="$tmp/brew.log" \
BREW_TEST_PREFIX="$tmp/homebrew" \
NIX_HM_BREW_BIN="$tmp/homebrew/bin/brew" \
PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
HOME="$tmp/home" \
bash "$repo_root/brew/install.sh"

log="$(cat "$tmp/brew.log")"
if [[ "$log" != *"homebrew-installer NONINTERACTIVE=1"* ]]; then
  echo "expected brew/install.sh to bootstrap Homebrew non-interactively when brew is missing" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

if [[ "$log" != *"sudo -n -v"* ]]; then
  echo "expected brew/install.sh to require a cached sudo session before unattended Homebrew install" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi

for trust_cmd in \
  "brew trust --formula daipeihust/tap/im-select" \
  "brew trust --formula gromgit/fuse/sshfs-mac"; do
  if [[ "$log" != *"$trust_cmd"* ]]; then
    echo "expected brew/install.sh to trust third-party Homebrew formulae before nix-darwin activation" >&2
    printf '%s\n' "$log" >&2
    exit 1
  fi
done

if [[ "$log" == *"brew bundle"* ]]; then
  echo "expected brew/install.sh to leave package management to nix-darwin" >&2
  printf '%s\n' "$log" >&2
  exit 1
fi
