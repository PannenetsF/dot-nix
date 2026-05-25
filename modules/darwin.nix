{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.emptyActivationPath = false;
  targets.darwin.linkApps = {
    enable = true;
    directory = "Applications/Home Manager Apps";
  };

  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ${../install-macos.sh}
  '';
}
