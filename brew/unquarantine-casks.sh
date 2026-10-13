#!/usr/bin/env bash
# Remove com.apple.quarantine from bare-binary Homebrew casks after
# `brew bundle` runs (nix-darwin activation and init.sh --upgrade).
#
# Why this is needed:
#   Homebrew tags every downloaded cask artifact with com.apple.quarantine.
#   Homebrew 7 removed every way to opt out -- the --no-quarantine flag, the
#   HOMEBREW_CASK_OPTS escape hatch and the Cask::Config plumbing were deleted
#   (Homebrew commit ba25213c81, "Remove leftover code for --no-quarantine").
#   Notarized .app casks only show a one-time LaunchServices prompt, and
#   Homebrew 7 carries that approval across cask upgrades when the signing
#   identity is unchanged (Cask::Upgrade#inherit_user_approval!). The casks
#   below instead install a bare CLI binary that is signed but NOT notarized
#   (`spctl --assess` reports "Unnotarized Developer ID", no stapled ticket):
#   Gatekeeper rejects every exec with "Apple cannot verify ... is free of
#   malware", and the upgrade-approval inheritance only covers Artifact::App,
#   so every cask upgrade re-breaks the binary until the xattr is cleared.
#
# Scope: `brew list --cask` enumerates artifact-level loose files, which live
# in the Caskroom and are clearable by their owner. This script deliberately
# does NOT touch /Applications or .app bundles: modifying those needs an
# interactive TCC App Management grant and fails EPERM even for root.
#
# Idempotent and conservative: touches only artifacts of the casks below,
# only removes the quarantine xattr, is a no-op off macOS / without brew /
# for absent casks, and never exits non-zero so it cannot break activation.
set -euo pipefail

BREW_BIN="${BREW_BIN:-brew}"

CASKS=(
  claude-code
  codex
)

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if ! command -v "$BREW_BIN" >/dev/null 2>&1; then
  echo "[unquarantine-casks] $BREW_BIN not found; skipping" >&2
  exit 0
fi

has_quarantine() {
  /usr/bin/xattr -p com.apple.quarantine "$1" >/dev/null 2>&1
}

# Remove the xattr from exactly one brew-list artifact path.
# Returns 0 only when an xattr was actually removed.
clear_one() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 1
  has_quarantine "$path" || return 1
  /usr/bin/xattr -d com.apple.quarantine "$path" 2>/dev/null || return 1
  has_quarantine "$path" && return 1
  return 0
}

for cask in "${CASKS[@]}"; do
  # Not installed -> brew list exits non-zero; skip quietly.
  paths="$("$BREW_BIN" list --cask "$cask" 2>/dev/null)" || continue

  cleared=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    # Install receipts/config are data, never executed; .app bundles cannot
    # be cleared without TCC App Management permission anyway.
    case "$path" in
      */.metadata/*|*.app) continue ;;
    esac

    if clear_one "$path"; then
      cleared=$((cleared + 1))
    fi
  done <<<"$paths"

  if (( cleared > 0 )); then
    echo "[unquarantine-casks] cleared com.apple.quarantine from $cask ($cleared path(s))" >&2
  fi
done
