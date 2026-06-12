{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.emptyActivationPath = false;
  home.file = {
    ".config/aerospace/aerospace.toml" = {
      source = ../config/aerospace/aerospace.toml;
      force = true;
    };

    ".aerospace.toml" = {
      source = ../config/aerospace/aerospace.toml;
      force = true;
    };

    ".config/skhd/skhdrc" = {
      source = ../config/skhd/skhdrc;
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
