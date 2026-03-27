{ config, pkgs, lib, ... }:
{
  home.file.".config/nix-hm/install-macos.sh" = {
    source = ../install-macos.sh;
    executable = true;
  };

  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ~/.config/nix-hm/install-macos.sh
  '';
}
