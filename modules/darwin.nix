{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.emptyActivationPath = false;

  home.file = {
    ".skhdrc" = {
      source = ../config/skhd/skhdrc;
      force = true;
    };

    ".config/skhd/open_iterm2.sh" = {
      source = ../config/skhd/open_iterm2.sh;
      executable = true;
      force = true;
    };

    ".config/karabiner/karabiner.json" = {
      source = ../config/karabiner/karabiner.json;
      force = true;
    };
  };

  services.skhd = {
    enable = true;
    config = builtins.readFile ../config/skhd/skhdrc;
  };

  home.activation.ensureDarwinLogDirectories =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.home.homeDirectory}/Library/Logs/skhd" \
        "${config.home.homeDirectory}/Pictures/Screenshots"
    '';

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
