{ config, pkgs, lib, ... }:
{
  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ~/.config/nix-hm/install-macos.sh
  '';
}
