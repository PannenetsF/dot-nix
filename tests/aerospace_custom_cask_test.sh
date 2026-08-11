#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cask="${repo_root}/config/homebrew/Casks/aerospace-patched.rb"

assert_contains() {
  local text="$1"
  local message="$2"

  if ! grep -Fq "$text" "$cask"; then
    echo "$message" >&2
    exit 1
  fi
}

ruby -c "$cask" >/dev/null

assert_contains 'version "0.21.3-Beta-pf.1"' \
  "expected the patched AeroSpace cask to pin its release version"
assert_contains 'sha256 "125ea00f5ece3ce55d14fd5b584fa2f5f1717a460894b526fd0c0a611a11dac1"' \
  "expected the patched AeroSpace cask to pin the verified release hash"
assert_contains 'PannenetsF/AeroSpace/releases/download/v#{version}/AeroSpace-v#{version}.zip' \
  "expected the patched AeroSpace cask to use the immutable fork release asset"
assert_contains '0141b97956c997decd6692d9602b7e49cf1fc939' \
  "expected the patched AeroSpace cask to record its source commit"
assert_contains '3121c4ba5862a49d834a2df301739ac95c08cc4a' \
  "expected the patched AeroSpace cask to record its release commit"
assert_contains 'app "AeroSpace-v#{version}/AeroSpace.app"' \
  "expected the patched cask to install the app bundle"
assert_contains 'binary "AeroSpace-v#{version}/bin/aerospace"' \
  "expected the patched cask to install its matching CLI"
assert_contains 'conflicts_with cask: ["aerospace", "aerospace-dev"]' \
  "expected the patched cask to guard against the upstream cask"

if grep -Fq 'file://' "$cask"; then
  echo "expected the patched AeroSpace cask not to depend on a local build path" >&2
  exit 1
fi

echo "AeroSpace custom cask tests passed"
