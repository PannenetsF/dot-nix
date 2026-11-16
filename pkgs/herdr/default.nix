# Selects the personal Herdr package for the host system:
#   - a published release binary (./binary.nix) when pin.releaseAssets has an
#     entry for this Nix system;
#   - otherwise the Nix source build (./source.nix).
# The caller chooses the package set (see mkHerdr in flake.nix): nixpkgs
# -unstable for every target with a release asset, nixos-26.05 for
# x86_64-darwin, the only target without one and whose Darwin stdenv unstable
# has removed. source.nix is package-set agnostic (both sets provide
# zig_0_16.fetchDeps; the agent-skills hook is vendored), so either works.
{ stdenv, callPackage, }:
let
  pin = import ./pin.nix;
  system = stdenv.hostPlatform.system;
in if pin.releaseAssets ? ${system} then
  callPackage ./binary.nix { inherit pin system; }
else
  callPackage ./source.nix { inherit pin; }
