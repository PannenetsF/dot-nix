#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load init.sh function definitions without invoking main.
init_funcs="$(/usr/bin/sed '/^main "\$@"$/d' "${repo_root}/init.sh")"

# --- current_system_brewfile parses the activated system's activate script ---

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "${tmp}/current-system"
cat >"${tmp}/current-system/activate" <<'ACTIVATE'
  PATH="/opt/homebrew/bin:$PATH" \
  sudo \
    --user=bytedance \
    --set-home \
    HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file='/nix/store/awwzcf6586sxgmij0qwn7ki8x9sx2rjf-Brewfile' --no-upgrade
ACTIVATE

(
  eval "$init_funcs"
  found="$(current_system_brewfile "${tmp}/current-system")"
  [[ "$found" == "/nix/store/awwzcf6586sxgmij0qwn7ki8x9sx2rjf-Brewfile" ]]
)

# Missing activate script -> failure, not an empty success.
if (
  eval "$init_funcs"
  current_system_brewfile "${tmp}/no-such-system"
) 2>/dev/null; then
  echo "expected current_system_brewfile to fail without an activate script" >&2
  exit 1
fi

# --- upgrade_homebrew_bundle: update then bundle --upgrade -------------------

mkdir -p "${tmp}/bin"
brew_log="${tmp}/brew.log"
cat >"${tmp}/bin/brew" <<'SH'
#!/usr/bin/env bash
{
  printf 'brew'
  for arg in "$@"; do printf ' %q' "$arg"; done
  printf '\n'
  [[ "${HOMEBREW_NO_REQUIRE_TAP_TRUST:-}" == "1" ]] \
    && printf 'NO_REQUIRE_TAP_TRUST=1\n'
  true
} >>"${BREW_STUB_LOG}"
SH
chmod +x "${tmp}/bin/brew"

(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  BREW_STUB_LOG="$brew_log" \
    upgrade_homebrew_bundle >/dev/null
)

grep -Fx 'brew update' "$brew_log"
grep -Fx "brew bundle --file=/nix/store/awwzcf6586sxgmij0qwn7ki8x9sx2rjf-Brewfile --upgrade" "$brew_log"

# update must run before bundle
first_non_update="$(grep -vn '^brew update$' "$brew_log" | head -1 | cut -d: -f1)"
last_update="$(grep -n '^brew update$' "$brew_log" | tail -1 | cut -d: -f1)"
[[ "$first_non_update" -gt "$last_update" ]]

# --- After bundle --upgrade, the unquarantine helper runs with the same brew -

unquarantine_log="${tmp}/unquarantine.log"
cat >"${tmp}/unquarantine.sh" <<SH
#!/usr/bin/env bash
echo "ran BREW_BIN=\$BREW_BIN" >>"${unquarantine_log}"
SH
chmod +x "${tmp}/unquarantine.sh"
: >"${unquarantine_log}"

(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  NIX_HM_UNQUARANTINE_SCRIPT="${tmp}/unquarantine.sh" \
  BREW_STUB_LOG="$brew_log" \
    upgrade_homebrew_bundle >/dev/null
)
grep -Fx "ran BREW_BIN=${tmp}/bin/brew" "$unquarantine_log"

# A failing `brew bundle --upgrade` entry (e.g. running app, TCC chgrp deny)
# must not abort the unquarantine pass after it.
fail_log="${tmp}/fail.log"
: >"$fail_log"
: >"$unquarantine_log"
cat >"${tmp}/bin/failbrew" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "bundle" ]] && exit 1
exit 0
SH
chmod +x "${tmp}/bin/failbrew"
cat >"${tmp}/unquarantine.sh" <<SH
#!/usr/bin/env bash
echo ran >>"${unquarantine_log}"
SH
(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/failbrew" \
  NIX_HM_UNQUARANTINE_SCRIPT="${tmp}/unquarantine.sh" \
    upgrade_homebrew_bundle >/dev/null 2>"${tmp}/fail.err"
)
grep -q 'some Homebrew upgrades failed' "${tmp}/fail.err"
[[ "$(grep -c '^ran$' "$unquarantine_log")" -eq 1 ]]

# A failing helper must not abort the upgrade path.
cat >"${tmp}/unquarantine.sh" <<'SH'
#!/usr/bin/env bash
exit 3
SH
(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  NIX_HM_UNQUARANTINE_SCRIPT="${tmp}/unquarantine.sh" \
  BREW_STUB_LOG="$brew_log" \
    upgrade_homebrew_bundle >/dev/null
)

# --- Missing brew binary: skip loudly without failure ------------------------

(
  set -euo pipefail
  eval "$init_funcs"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
    upgrade_homebrew_bundle 2>"${tmp}/skip.err" >/dev/null
)
grep -q 'skipping formula/cask upgrade' "${tmp}/skip.err"

# --- Missing Brewfile: fatal so a silently skipped upgrade is noticed --------

if (
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/no-such-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  BREW_STUB_LOG="$brew_log" \
    upgrade_homebrew_bundle 2>/dev/null
); then
  echo "expected upgrade_homebrew_bundle to die when the Brewfile is missing" >&2
  exit 1
fi

# --- Wiring: only hm-upgrade upgrades brew; hm-update stays install-only -----

if ! grep -q 'upgrade_homebrew_bundle' "${repo_root}/init.sh"; then
  echo "expected init.sh to call upgrade_homebrew_bundle" >&2
  exit 1
fi
if ! grep -A3 'onActivation = {' "${repo_root}/nix-darwin/homebrew.nix" \
     | grep -q 'upgrade = false'; then
  echo "expected nix-darwin onActivation upgrade = false so hm-update never upgrades brew" >&2
  exit 1
fi

# --- converge_homebrew_bundle: cleanup --force + trust repair ----------------

converge_system="${tmp}/converge-system"
mkdir -p "$converge_system"
converge_brewfile="${tmp}/converge.Brewfile"
cat >"$converge_brewfile" <<'BREWFILE'
tap "d12frosted/emacs-plus"
tap "dot-nix/local", "/Users/me/.cache/dot-nix/homebrew-local-tap"
brew "aspell"
cask "kitty"
BREWFILE
cat >"$converge_system/activate" <<ACTIVATE
  brew bundle --file='${converge_brewfile}' --no-upgrade
ACTIVATE

converge_log="${tmp}/converge.log"
: >"$converge_log"
(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_SYSTEM_BREWFILE="$converge_brewfile" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  BREW_STUB_LOG="$converge_log" \
    converge_homebrew_bundle >/dev/null
)

# Every Brewfile tap is trusted both before (loading the Brewfile needs it)
# and after (cleanup --force replaces the trust store).
[[ "$(grep -c -Fx 'brew trust --quiet d12frosted/emacs-plus' "$converge_log")" -eq 2 ]]
[[ "$(grep -c -Fx 'brew trust --quiet dot-nix/local' "$converge_log")" -eq 2 ]]

grep -Fx "brew bundle --file=$converge_brewfile cleanup --force" "$converge_log"
grep -Fx 'brew cleanup' "$converge_log"

# The destructive cleanup pass must bypass the tap-trust gate: --force
# replaces the trust store mid-run, which would otherwise hide third-party
# formula dep trees (emacs-plus) and get their dependencies uninstalled.
[[ "$(grep -c -Fx 'NO_REQUIRE_TAP_TRUST=1' "$converge_log")" -eq 1 ]]
grep -A1 -Fx "brew bundle --file=$converge_brewfile cleanup --force" "$converge_log" \
  | tail -1 | grep -Fxq 'NO_REQUIRE_TAP_TRUST=1'

# Ordering: first trust -> bundle cleanup --force -> second trust -> cache pass.
{
  grep -n -m1 'brew trust --quiet d12frosted/emacs-plus' "$converge_log" | cut -d: -f1
  grep -n -m1 "cleanup --force" "$converge_log" | cut -d: -f1
  grep -n -m2 'brew trust --quiet d12frosted/emacs-plus' "$converge_log" | tail -1 | cut -d: -f1
  grep -n -m1 '^brew cleanup$' "$converge_log" | cut -d: -f1
} | sort -cn

# Missing brew binary: skip without failure.
(
  set -euo pipefail
  eval "$init_funcs"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  NIX_HM_CURRENT_SYSTEM="$converge_system" \
    converge_homebrew_bundle 2>"${tmp}/converge-skip.err" >/dev/null
)
grep -q 'skipping brew bundle cleanup' "${tmp}/converge-skip.err"

# Missing/unreadable Brewfile: skip with a warning, never fatal.
(
  set -euo pipefail
  eval "$init_funcs"
  NIX_HM_CURRENT_SYSTEM="${tmp}/no-such-system" \
  NIX_HM_BREW_BIN="${tmp}/bin/brew" \
  BREW_STUB_LOG="$converge_log" \
    converge_homebrew_bundle 2>"${tmp}/converge-nobf.err" >/dev/null
)
grep -q 'could not locate the active system Brewfile' "${tmp}/converge-nobf.err"

# --- Wiring: converge runs on every darwin switch; nix-darwin must not emit
# Homebrew 7's removed --cleanup flag (onActivation.cleanup stays "none").

grep -q 'converge_homebrew_bundle' "${repo_root}/init.sh"
if ! grep -A12 'onActivation = {' "${repo_root}/nix-darwin/homebrew.nix" \
     | grep -q 'cleanup = "none"'; then
  echo 'expected nix-darwin onActivation cleanup = "none" (Homebrew 7 removed --cleanup)' >&2
  exit 1
fi

echo "init brew upgrade test OK"
