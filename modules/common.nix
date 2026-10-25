{
  config,
  pkgs,
  pkgsUnstable,
  lib,
  system ? pkgs.stdenv.hostPlatform.system,
  ...
}:
let
  isDarwin = lib.hasSuffix "-darwin" system;
  shellProfileInit = ''
    # Source Nix profile
    if [ -e "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
      . "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    elif [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    fi

    # Move a directory to the front of PATH, dropping any existing
    # occurrence first. Plain "prepend if absent" cannot fix ordering:
    # nix-darwin's set-environment (/etc/zshenv) seeds every shell with
    # all three Nix profile dirs already in PATH, so a presence check
    # would skip reordering entirely and let Homebrew (added below) win.
    _nix_hm_path_to_front() {
      case ":$PATH:" in
        *":$1:"*)
          PATH=":$PATH:"
          PATH=''${PATH//:"$1":/:}
          PATH=''${PATH#:}; PATH=''${PATH%:} ;;
      esac
      PATH="$1:$PATH"
    }

    # Make Homebrew CLI tools available on macOS, but never ahead of the
    # Nix profiles (added-if-missing here, then pushed back by the reorder
    # below): this machine is Nix-managed and host.nix deliberately ships
    # python3/ruff/cmake/node/git etc. Letting Homebrew sit in front
    # split `python` (Nix 3.12) from `python3` (Homebrew 3.14, which
    # ships no `python` shim). GUI apps are unaffected - LaunchServices
    # sessions use emacs-plus' frozen EMACS_PLUS_PATH snapshot.
    ${lib.optionalString isDarwin ''
      for _nix_hm_brew_path in /usr/local/sbin /usr/local/bin /opt/homebrew/sbin /opt/homebrew/bin; do
        if [ -d "$_nix_hm_brew_path" ]; then
          case ":$PATH:" in
            *":$_nix_hm_brew_path:"*) ;;
            *) export PATH="$_nix_hm_brew_path:$PATH" ;;
          esac
        fi
      done
      unset _nix_hm_brew_path
    ''}

    # Force the Nix profile dirs to the front even when they were seeded
    # further down PATH by nix-darwin's set-environment.
    for _nix_hm_nix_path in /run/current-system/sw/bin "/etc/profiles/per-user/''${USER:-}/bin" "$HOME/.nix-profile/bin"; do
      [ -d "$_nix_hm_nix_path" ] && _nix_hm_path_to_front "$_nix_hm_nix_path"
    done
    unset _nix_hm_nix_path
    export PATH

    # Source Home Manager session variables after profile PATH is available.
    _nix_hm_had_nounset=
    case $- in
      *u*) _nix_hm_had_nounset=1; set +u ;;
    esac
    if [ -n "''${USER:-}" ] && [ -e "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh" ]; then
      . "/etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh"
    elif [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    fi
    if [ -n "$_nix_hm_had_nounset" ]; then
      set -u
    fi
    unset _nix_hm_had_nounset

    # Claude Code trust shim: ~/.local/bin/claude-shim/claude pre-accepts the
    # per-folder "Do you trust the files in this folder?" dialog (no official
    # switch exists; acceptance is a flag in ~/.claude.json), so agent sessions
    # started by herdr-projects in brand-new folders never stall on an
    # interactive prompt. Must sit ahead of /opt/homebrew/bin (prepended above)
    # and of $HOME/.local/bin (hm-session-vars).
    case ":$PATH:" in
      *":$HOME/.local/bin/claude-shim:"*) ;;
      *) export PATH="$HOME/.local/bin/claude-shim:$PATH" ;;
    esac
  '';
in {
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
      pkgsUnstable.fd
      pkgsUnstable.tree-sitter
      pkgs.vim-language-server
      pkgs.universal-ctags
    ];

    # Claude Code trust shim, prepended to PATH at the end of shellProfileInit
    # above. Bash-only and portable, so it ships on every host layer; on hosts
    # without claude the wrapper is simply never invoked.
    file.".local/bin/claude-shim/claude" = {
      source = ../config/claude/claude-shim.sh;
      executable = true;
      force = true;
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

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

      ${shellProfileInit}

      # Set TERM with fallback
      if [ "$TERM" != "xterm-kitty" ] && [ "$TERM" != "xterm-256color" ]; then
        if command -v infocmp >/dev/null 2>&1 && infocmp xterm-kitty >/dev/null 2>&1; then
          export TERM="xterm-kitty"
        else
          export TERM="xterm-256color"
        fi
      fi

      # <<<<< Prefix history search
      #
      # Type a prefix, then Up/Down to search history for that prefix.
      autoload -U up-line-or-beginning-search down-line-or-beginning-search
      zle -N up-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search
      #
      # Prefix history search >>>>>

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
      alias hm-update="bash $HOME/.config/nix-hm/init.sh"
      alias hm-upgrade="bash $HOME/.config/nix-hm/init.sh --upgrade"

      # Machine-local zsh customizations. Keep tokens and private aliases out of git.
      if [ -r "$HOME/.config/nix-hm/local.zsh" ]; then
        . "$HOME/.config/nix-hm/local.zsh"
      fi
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$character$directory$git_branch$git_status";
      directory = {
        truncation_length = 1;
        truncate_to_repo = false;
        format = "[$path]($style) ";
      };
      git_branch = {
        format = "[git:\\(](bold blue)[$branch](bold red)[\\)](bold blue)";
      };
      git_status = {
        format = "[ ✗](yellow)";
        conflicted = "";
        ahead = "";
        behind = "";
        up_to_date = "";
        untracked = "";
        stashed = "";
        modified = "";
        staged = "";
        renamed = "";
        deleted = "";
        typechanged = "";
      };
      character = {
        success_symbol = "[➜](bold green) ";
        error_symbol = "[✗](bold red) ";
      };
    };
  };

  programs.bash = {
    enable = true;
    # macOS still ships /bin/bash 3.2. Home Manager's bash-completion hook uses
    # Bash 4+ syntax, so keep completion off for compatibility with login bash.
    enableCompletion = false;
    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
    ];
    profileExtra = shellProfileInit;
    bashrcExtra = shellProfileInit;
    shellAliases = {
      work = "cd $HOME/Documents/workspace/ || cd $HOME/workspace";
      gomounts = "cd $HOME/Documents/workspace/mounts/";
      hm-update = "bash $HOME/.config/nix-hm/init.sh";
      hm-upgrade = "bash $HOME/.config/nix-hm/init.sh --upgrade";
    };
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
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.home-manager.enable = true;
}
