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

    ".config/kitty/kitty.conf" = {
      source = ../config/kitty/kitty.conf;
      force = true;
    };

    ".config/kitty/tab_bar.py" = {
      source = ../config/kitty/tab_bar.py;
      force = true;
    };

    ".config/kitty/theme.conf" = {
      source = ../config/kitty/theme.conf;
      force = true;
    };

    ".config/kitty/dark-theme.auto.conf" = {
      source = ../config/kitty/dark-theme.auto.conf;
      force = true;
    };

    ".config/kitty/light-theme.auto.conf" = {
      source = ../config/kitty/light-theme.auto.conf;
      force = true;
    };

    ".config/kitty/no-preference-theme.auto.conf" = {
      source = ../config/kitty/no-preference-theme.auto.conf;
      force = true;
    };

    ".config/kitty/saved-session.conf" = {
      source = ../config/kitty/saved-session.conf;
      force = true;
    };

    ".config/neovide/config.toml" = {
      source = ../config/neovide/config.toml;
      force = true;
    };

    ".config/zed/settings.json" = {
      source = ../config/zed/settings.json;
      force = true;
    };

    ".config/zed/keymap.json" = {
      source = ../config/zed/keymap.json;
      force = true;
    };

    ".config/zed/tasks.json" = {
      source = ../config/zed/tasks.json;
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

  home.activation.prepareKittyConfig =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      kitty_config="${config.home.homeDirectory}/.config/kitty"
      if [ -L "$kitty_config" ]; then
        rm -f "$kitty_config"
      elif [ -d "$kitty_config/.git" ]; then
        rm -rf "$kitty_config"
      fi
      mkdir -p "$kitty_config"
      unset kitty_config
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
