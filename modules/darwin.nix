{ config, pkgs, lib, ... }:
{
  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ${../install-macos.sh}
  '';
}
