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

  home.activation.runMyScript = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ -e "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    fi
    export PATH="${config.home.profileDirectory}/bin:$PATH"
    bash ${../install-macos.sh}
  '';
}
