{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.emptyActivationPath = false;
  home.packages = [ pkgs.aerospace ];

  home.file = {
    ".config/aerospace/aerospace.toml" = {
      source = ../config/aerospace/aerospace.toml;
      force = true;
    };

    ".aerospace.toml" = {
      source = ../config/aerospace/aerospace.toml;
      force = true;
    };

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

  launchd.agents.aerospace = {
    enable = true;
    config = {
      Program =
        "${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath =
        "${config.home.homeDirectory}/Library/Logs/aerospace/aerospace.out.log";
      StandardErrorPath =
        "${config.home.homeDirectory}/Library/Logs/aerospace/aerospace.err.log";
    };
  };

  targets.darwin.linkApps = {
    enable = true;
    directory = "Applications/Home Manager Apps";
  };

  home.activation.ensureDarwinLogDirectories =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${config.home.homeDirectory}/Library/Logs/aerospace" \
        "${config.home.homeDirectory}/Library/Logs/skhd" \
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
