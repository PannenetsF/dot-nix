#!/usr/bin/env bash
set -euo pipefail

# The personal TRAE-enabled Herdr (PannenetsF/herdr fork) must be a Nix
# package selected per system in pkgs/herdr, wired into both the macOS
# (nix-darwin + embedded Home Manager) and Linux host layers, and must never
# resolve back to the Homebrew core formula or an official per-user binary.
# Combines static assertions with nix eval (no build).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "expected $1 to contain: $2"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail "did not expect $1 to contain: $2"
  fi
}

nix_eval() {
  nix --extra-experimental-features 'nix-command flakes' eval --impure "$@" 2>/dev/null
}

# --- Package tree -----------------------------------------------------------
for f in pkgs/herdr/default.nix pkgs/herdr/source.nix pkgs/herdr/binary.nix pkgs/herdr/pin.nix; do
  [[ -f "$f" ]] || fail "expected $f to be tracked"
done

# nixos-26.05 lacks the top-level installAgentSkills attr, so the agent-skills
# setup hook is vendored locally and referenced from the source build.
[[ -f pkgs/herdr/install-agent-skills/default.nix ]] \
  || fail "expected the vendored install-agent-skills hook"
[[ -f pkgs/herdr/install-agent-skills/setup-hook.sh ]] \
  || fail "expected the vendored install-agent-skills setup-hook.sh"
assert_contains pkgs/herdr/source.nix './install-agent-skills'

# The pin names the personal fork and a personal -traex tag, never upstream
# herdrdev/herdr or a plain upstream version.
assert_contains pkgs/herdr/pin.nix 'owner = "PannenetsF"'
assert_contains pkgs/herdr/pin.nix 'repo = "herdr"'
assert_contains pkgs/herdr/pin.nix 'v0.9.5-traex.'
if grep -Eq 'owner = "herdrdev"' pkgs/herdr/pin.nix; then
  fail "pin must target the personal PannenetsF fork, not herdrdev"
fi

# Both consumption paths exist: source build and prebuilt release binary.
assert_contains pkgs/herdr/source.nix 'rustPlatform.buildRustPackage'
assert_contains pkgs/herdr/source.nix 'fetchFromGitHub'
assert_contains pkgs/herdr/binary.nix 'fetchurl'
# The selector prefers a published asset and falls back to the source build.
assert_contains pkgs/herdr/default.nix 'pin.releaseAssets'
assert_contains pkgs/herdr/default.nix './source.nix'
assert_contains pkgs/herdr/default.nix './binary.nix'
# Every build path proves the TRAE CLI surface, not just a version string.
assert_contains pkgs/herdr/source.nix 'grep -q traex'
assert_contains pkgs/herdr/binary.nix 'grep -q traex'
# Both paths also ship shell completions (the bare release assets do not bundle
# them), generated only when the build machine can execute the result.
assert_contains pkgs/herdr/source.nix 'installShellCompletion'
assert_contains pkgs/herdr/binary.nix 'installShellCompletion'
assert_contains pkgs/herdr/binary.nix 'canExecute stdenv.hostPlatform'

# --- Flake wiring -----------------------------------------------------------
assert_contains flake.nix 'mkHerdr'
assert_contains flake.nix './pkgs/herdr'
assert_contains flake.nix 'herdrPkg = mkHerdr system'
# nixpkgs-unstable dropped x86_64-darwin; the declared target needs the
# documented force-allow or the Intel Mac package can no longer instantiate.
assert_contains flake.nix 'allowDeprecatedx86_64Darwin = "force"'
# The Intel Darwin source build is pinned to the last nixpkgs release that
# still ships the x86_64-darwin stdenv plus zig_0_16.
assert_contains flake.nix 'nixpkgs-26_05.url'
assert_contains flake.nix 'system == "x86_64-darwin"'
# The package is exposed for direct builds on all four supported systems.
for s in x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin; do
  grep -Fq "\"$s\"" flake.nix || fail "flake must still declare system $s"
done

# --- macOS module wiring ----------------------------------------------------
# The activation CLI is the Nix package, not the Homebrew prefix binary.
assert_contains nix-darwin/herdr.nix 'herdrCli = "${herdrPkg}/bin/herdr"'
assert_contains nix-darwin/herdr.nix 'herdrPkg'
assert_not_contains nix-darwin/herdr.nix 'brewPrefix}/herdr'
# The embedded Home Manager user layer also installs the package so the
# profile bin shadows Homebrew on PATH.
assert_contains modules/darwin.nix 'home.packages = [ herdrPkg ]'
# The Homebrew declarative set must not pull the core formula back in.
if grep -Eq '^[[:space:]]*"herdr"[[:space:]]*$' nix-darwin/homebrew.nix; then
  fail "homebrew.nix must not declare the core herdr formula"
fi
# The relay polls the pinned Nix binary via an absolute HERDR_BIN.
assert_contains nix-darwin/herdr-remote.nix 'export HERDR_BIN="${herdrPkg}/bin/herdr"'
assert_contains nix-darwin/herdr-remote.nix 'herdrPkg'

# --- Linux module wiring ----------------------------------------------------
assert_contains modules/herdr.nix 'home.packages = [ herdrPkg ]'
assert_contains modules/herdr.nix 'HERDR_CLI="${herdrPkg}/bin/herdr"'
assert_contains modules/herdr.nix 'export PATH="${herdrPkg}/bin:'

# --- Nix eval: package instantiates on every supported system ---------------
for s in x86_64-linux aarch64-linux x86_64-darwin aarch64-darwin; do
  name="$(nix_eval .#packages.$s.herdr.name)" \
    || fail "herdr package does not evaluate for $s"
  [[ "$name" == *"herdr-0.9.5-traex."* ]] \
    || fail "unexpected herdr package name on $s: $name"
done

# Three targets consume a published release binary; x86_64-darwin (no release
# asset, unstable stdenv removed) is the sole source build. meta.description
# differs between binary.nix and source.nix, making the mode observable.
is_prebuilt() {
  nix_eval .#packages."$1".herdr.meta.description \
    | grep -Fq 'prebuilt release binary'
}
for s in aarch64-darwin x86_64-linux aarch64-linux; do
  is_prebuilt "$s" || fail "$s must use the prebuilt release binary"
done
if is_prebuilt x86_64-darwin; then
  fail "x86_64-darwin has no release asset and must build from source"
fi

# The x86_64-darwin source build must instantiate a real derivation, proving
# the nixos-26.05 Intel Darwin stdenv gate is actually passed (a name-only eval
# succeeds even when drvPath throws "Unsupported platform for the Darwin
# stdenv").
nix_eval .#packages.x86_64-darwin.herdr.drvPath \
  | grep -Fq '.drv' || fail "x86_64-darwin herdr drvPath does not instantiate"

# home.packages can hold non-derivation entries, so tolerate missing pname.
has_herdr='ps: builtins.any (p: (p.pname or p.name or "") == "herdr") ps'

# --- Nix eval: host layers install it, the docker layer must not -------------
linux_host="$(
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.x86_64-linux-host.config.home.packages --apply "$has_herdr"
)"
[[ "$linux_host" == "true" ]] || fail "Linux host profile must include the herdr package"

arm_host="$(
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.aarch64-linux-host.config.home.packages --apply "$has_herdr"
)"
[[ "$arm_host" == "true" ]] || fail "aarch64 Linux host profile must include the herdr package"

docker_layer="$(
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.x86_64-linux-docker.config.home.packages --apply "$has_herdr"
)"
[[ "$docker_layer" == "false" ]] || fail "docker layer must stay lean and not install herdr"

# Standalone macOS Home Manager config (isHost=true) carries the package too.
darwin_hm="$(
  USER=alice HOME=/Users/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix_eval .#homeConfigurations.aarch64-darwin.config.home.packages --apply "$has_herdr"
)"
[[ "$darwin_hm" == "true" ]] || fail "macOS Home Manager layer must include the herdr package"

# The nix-darwin system config threads herdrPkg into both its own module and
# the embedded Home Manager.
darwin_sys="$(
  USER=root HOME=/tmp/nix-hm-root NIX_HM_USER=bytedance NIX_HM_HOME=/Users/bytedance \
    nix_eval .#darwinConfigurations.aarch64-darwin.config.system.primaryUser
)"
[[ "$darwin_sys" == *"bytedance"* ]] || fail "darwin system config failed to evaluate with herdrPkg"

echo "herdr package wiring test OK"
