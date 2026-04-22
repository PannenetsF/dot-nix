{ config, pkgs, pkgsUnstable, lib, ... }:
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
      pkgsUnstable.clang-tools
      pkgsUnstable.fzf
      pkgsUnstable.ripgrep
      pkgs.nodePackages.vim-language-server
      pkgs.universal-ctags
    ];
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

    initContent = ''
      # Disable marking untracked files under VCS as dirty to speed up repository status checks
      export DISABLE_UNTRACKED_FILES_DIRTY="true"

      # NVM Lazy Loading: 极大加速 zsh 启动
      export NVM_DIR="$HOME/.nvm"
      zsh_nvm_lazy_load() {
        unset -f node npm npx yarn pnpm nvm
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
      }
      node() { zsh_nvm_lazy_load; node "$@" }
      npm() { zsh_nvm_lazy_load; npm "$@" }
      npx() { zsh_nvm_lazy_load; npx "$@" }
      yarn() { zsh_nvm_lazy_load; yarn "$@" }
      pnpm() { zsh_nvm_lazy_load; pnpm "$@" }
      nvm() { zsh_nvm_lazy_load; nvm "$@" }

      # Source Nix profile
      if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
      elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix.sh"
      fi

      # Set TERM with fallback
      if [ "$TERM" != "xterm-kitty" ] && [ "$TERM" != "xterm-256color" ]; then
        if command -v infocmp >/dev/null 2>&1 && infocmp xterm-kitty >/dev/null 2>&1; then
          export TERM="xterm-kitty"
        else
          export TERM="xterm-256color"
        fi
      fi

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

      alias work="cd $HOME/Documents/workspace/ || cd $HOME/workspace"
      alias gomounts="cd $HOME/Documents/workspace/mounts/"
      alias hm-update="[ -f $HOME/Documents/workspace/dot-nix/init.sh ] && bash $HOME/Documents/workspace/dot-nix/init.sh || bash $HOME/.config/nix-hm/init.sh"
      alias hm-upgrade="[ -f $HOME/Documents/workspace/dot-nix/init.sh ] && bash $HOME/Documents/workspace/dot-nix/init.sh --upgrade || bash $HOME/.config/nix-hm/init.sh --upgrade"
    '';
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    package = pkgsUnstable.neovim-unwrapped;
  };

  programs.tmux = {
    extraConfig = ''
      set-option -a terminal-features "xterm:RGB"
    '';
  };

  home.sessionVariables = {
    PATH = "$HOME/.local/bin:$PATH";
    LC_ALL = "C.UTF-8";
    COLORTERM = "truecolor";
  };

  programs.home-manager.enable = true;
}
