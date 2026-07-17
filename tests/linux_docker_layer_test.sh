#!/usr/bin/env bash
set -euo pipefail

# Verifies the Linux container (Docker) layer: it composes through home.nix,
# stays lean (no host toolchain), and -- crucially -- does NOT wire the
# network-dependent install-linux-server.sh activation that the desktop/server
# Linux layer runs.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_eval() {
  USER=alice HOME=/home/alice XDG_CACHE_HOME=/tmp/nix-hm-eval-cache \
    nix --extra-experimental-features 'nix-command flakes' eval --impure "$@" 2>/dev/null
}

assert_eq() {
  local actual="$1" expected="$2" context="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected %s to be %s, got %s\n' "$context" "$expected" "$actual" >&2
    exit 1
  fi
}

# The module must exist and be selected only for the docker profile.
if [[ ! -f "$repo_root/modules/linux-docker.nix" ]]; then
  echo "expected modules/linux-docker.nix to exist" >&2
  exit 1
fi

# Docker layer must NOT run install-linux-server.sh (no runMyScript activation).
docker_has_runmyscript="$(
  nix_eval .#homeConfigurations.aarch64-linux-docker.config.home.activation \
    --apply 'a: a ? runMyScript'
)"
assert_eq "$docker_has_runmyscript" "false" \
  "aarch64-linux-docker install-linux-server.sh activation"

# The desktop/server Linux layer must keep running it.
desktop_has_runmyscript="$(
  nix_eval .#homeConfigurations.aarch64-linux.config.home.activation \
    --apply 'a: a ? runMyScript'
)"
assert_eq "$desktop_has_runmyscript" "true" \
  "aarch64-linux install-linux-server.sh activation"

# Docker layer must be lean: it excludes the host toolchain, so it carries the
# same package count as the plain desktop profile and fewer than the host one.
docker_pkgs="$(
  nix_eval .#homeConfigurations.aarch64-linux-docker.config.home.packages \
    --apply 'ps: builtins.length ps'
)"
host_pkgs="$(
  nix_eval .#homeConfigurations.aarch64-linux-host.config.home.packages \
    --apply 'ps: builtins.length ps'
)"
if [[ -z "$docker_pkgs" || -z "$host_pkgs" || "$docker_pkgs" -ge "$host_pkgs" ]]; then
  echo "expected docker layer ($docker_pkgs) to carry fewer packages than host ($host_pkgs)" >&2
  exit 1
fi

# init.sh must expose the docker profile and reject combining it with host.
if ! grep -Fq -- "--docker" "$repo_root/init.sh"; then
  echo "expected init.sh to accept a --docker flag" >&2
  exit 1
fi
if ! grep -Fq "linux-docker" "$repo_root/flake.nix"; then
  echo "expected flake.nix to declare the linux-docker home configurations" >&2
  exit 1
fi
