#!/usr/bin/env bash
set -euo pipefail

failures=0

if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

fail() {
  echo "[FAIL] $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "[ OK ] $*"
}

require_darwin() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "this acceptance check must run on macOS"
    return 1
  fi
}

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    pass "command available: $name"
  else
    fail "missing command: $name"
  fi
}

check_app() {
  local app="$1"
  if [[ -d "/Applications/${app}.app" || -d "${HOME}/Applications/${app}.app" ]]; then
    pass "app installed: $app"
  else
    fail "missing app: $app"
  fi
}

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    pass "path exists: $path"
  else
    fail "missing path: $path"
  fi
}

check_default() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(defaults read "$domain" "$key" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "default ${domain} ${key} = ${expected}"
  else
    fail "default ${domain} ${key}: expected '${expected}', got '${actual}'"
  fi
}

check_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$plist" 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    pass "plist ${plist} ${key} = ${expected}"
  else
    fail "plist ${plist} ${key}: expected '${expected}', got '${actual}'"
  fi
}

check_launch_agent() {
  local label="$1"
  local uid
  uid="$(id -u)"

  if launchctl print "gui/${uid}/${label}" >/dev/null 2>&1; then
    pass "launch agent loaded: $label"
  else
    fail "launch agent not loaded: $label"
  fi
}

require_darwin || true

check_command nix
check_command brew
check_command duti

for app in \
  "1Password" \
  "Firefox" \
  "Karabiner-Elements" \
  "kitty" \
  "Maccy" \
  "Raycast" \
  "Snipaste" \
  "Visual Studio Code" \
  "Zed" \
  "Zotero"; do
  check_app "$app"
done

check_path "${HOME}/.config/aerospace/aerospace.toml"
check_path "${HOME}/.aerospace.toml"
check_path "${HOME}/.config/skhd/skhdrc"
check_path "${HOME}/.skhdrc"
check_path "${HOME}/.config/skhd/open_iterm2.sh"
check_path "${HOME}/.config/karabiner/karabiner.json"
check_path "${HOME}/Pictures/Screenshots"

if grep -Riq "emacs" "${HOME}/.config/aerospace" "${HOME}/.aerospace.toml" 2>/dev/null; then
  fail "unexpected Emacs reference in AeroSpace config"
else
  pass "AeroSpace config has no Emacs reference"
fi

if grep -Fq "start-at-login = false" "${HOME}/.config/aerospace/aerospace.toml"; then
  pass "AeroSpace self-managed login startup disabled"
else
  fail "AeroSpace self-managed login startup is not disabled"
fi

check_launch_agent org.nix-community.home.aerospace
check_launch_agent org.nix-community.home.skhd

check_default -g ApplePressAndHoldEnabled 0
check_default -g KeyRepeat 2
check_default com.apple.dock autohide 1
check_default com.apple.finder ShowPathbar 1
check_default com.raycast.macos raycastPreferredWindowMode compact
check_plist_value "${HOME}/Library/Preferences/org.p0deje.Maccy.plist" historySize 200

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} acceptance check(s) failed" >&2
  exit 1
fi

echo "macOS acceptance checks passed"
