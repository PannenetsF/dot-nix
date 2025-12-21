{ config, pkgs, pkgsUnstable, ... }:

{
  home = {
    packages = [
      pkgs.lazygit
      pkgs.git
      pkgs.tmux
      pkgs.wget
      pkgs.curl
      pkgs.lua
      pkgs.gdb
      pkgs.nixfmt-classic
      pkgs.kitty
      pkgs.emacs
      pkgsUnstable.clang-tools
      pkgsUnstable.fzf
      pkgsUnstable.ripgrep
      pkgs.nodePackages.vim-language-server
      pkgs.universal-ctags
    ];

    # Don't ever change this after the first build.
    # It tells home-manager what the original state schema
    # was, so it knows how to go to the next state.  It
    # should NOT update when you update your system!
    stateVersion = "25.11";
  };
  programs.home-manager.enable = true;
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "robbyrussell";

    };

    initContent = ''
      # <<<<< Enable natural text editing
      #
      # Move to the beginning of the line. `Cmd + Left Arrow`:
      bindkey "^[[1;9D" beginning-of-line
      # Move to the end of the line. `Cmd + Right Arrow`:
      bindkey "^[[1;9C" end-of-line
      # Move to the beginning of the previous word. `Option + Left Arrow`:
      bindkey "^[[1;3D" backward-word
      # Move to the beginning of the next word. `Option + Right Arrow`:
      bindkey "^[[1;3C" forward-word
      # Delete the word behind the cursor. `Option + Delete`:
      bindkey "^[[3;10~" backward-kill-word
      # Delete the word after the cursor. `Option + fn + Delete`:
      bindkey "^[[3;3~" kill-word
      #
      # Enable natural text editing >>>>>
    '';
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    package = pkgsUnstable.neovim-unwrapped;
  };

  programs.kitty = {
    enable = true;
    settings = {
      confirm_os_window_close = 0;
      dynamic_background_opacity = true;
    };
  };

  home.sessionVariables = { PATH = "$HOME/.local/bin:$PATH"; };

  home.emptyActivationPath = false;
}
