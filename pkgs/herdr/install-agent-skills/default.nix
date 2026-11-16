# Local copy of nixpkgs' installAgentSkills setup hook. nixpkgs-unstable ships
# the top-level `installAgentSkills` attr, but nixos-26.05 — the package set
# used for the x86_64-darwin source build, because it is the last release that
# still ships an Intel Darwin stdenv — predates that attr. Vendoring the hook
# here keeps pkgs/herdr/source.nix buildable on either package set and still
# ships the one bundled agent skill (skills/herdr/SKILL.md). The hook body is
# copied verbatim from nixpkgs (MIT).
{ lib, makeSetupHook, }:
makeSetupHook {
  name = "herdr-install-agent-skills";
  meta = {
    description = "Install Herdr agent skills into share/skills";
    license = lib.licenses.mit;
  };
} ./setup-hook.sh
