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

# --- Missing brew binary: skip loudly without failure ------------------------

(
  set -euo pipefail
  eval "$init_funcs"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  NIX_HM_CURRENT_SYSTEM="${tmp}/current-system" \
    upgrade_homebrew_bundle 2>"${tmp}/skip.err" >/dev/null
)
grep -q '跳过 formula/cask 升级' "${tmp}/skip.err"

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

echo "init brew upgrade test OK"
