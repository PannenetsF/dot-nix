{ config, pkgs, pkgsUnstable, lib, ... }: {
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
      pkgsUnstable.clang-tools
      pkgsUnstable.fzf
      pkgsUnstable.ripgrep
      pkgs.nodePackages.vim-language-server
    ];

    # This needs to be set to your actual username.
    username = "root";
    homeDirectory = "/root";

    # Don't ever change this after the first build.
    # It tells home-manager what the original state schema
    # was, so it knows how to go to the next state.  It
    # should NOT update when you update your system!
    stateVersion = "25.05";
  };
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
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    package = pkgsUnstable.neovim-unwrapped;
  };
  programs.home-manager.enable = true;

  home.sessionVariables = { PATH = "$HOME/.local/bin:$PATH"; };
  
  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ~/.config/nix-hm/install-linux-server.sh
  '';

}
