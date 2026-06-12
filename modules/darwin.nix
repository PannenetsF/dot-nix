{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.emptyActivationPath = false;
  home.file.".config/karabiner/karabiner.json" = {
    source = ../config/karabiner/karabiner.json;
    force = true;
  };

  targets.darwin.linkApps = {
    enable = true;
    directory = "Applications/Home Manager Apps";
  };

  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ${../install-macos.sh}
  '';
}
