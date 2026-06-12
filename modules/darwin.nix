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
      case $- in
        *u*) hm_nounset_was_enabled=1 ;;
        *) hm_nounset_was_enabled=0 ;;
      esac
      set +u
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
      if [ "$hm_nounset_was_enabled" = 1 ]; then
        set -u
      fi
      unset hm_nounset_was_enabled
    fi
    export PATH="${config.home.profileDirectory}/bin:$PATH"
    bash ${../install-macos.sh}
  '';
}
