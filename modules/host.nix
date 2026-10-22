{ pkgs, pkgsUnstable, lib, ... }:
let
  pythonEnv = pkgs.python3.withPackages (pythonPackages:
    with pythonPackages; [
      jedi-language-server
      pip
      pynvim
      ruff
    ]);
in {
  home.packages = (with pkgs; [
    aerc
    automake
    bash-language-server
    cmake
    docker
    dockerfile-language-server-nodejs
    fastfetch
    gcc
    git-filter-repo
    gnuplot
    graphviz
    helix
    htop
    hugo
    imagemagick
    ispell
    jq
    ltex-ls
    libgccjit
    libsodium
    lnav
    luarocks
    lua-language-server
    mermaid-cli
    ninja
    nodejs_22
    pandoc
    pkgconf
    poppler
    pythonEnv
    shfmt
    stylua
    vscode-langservers-extracted
    yaml-language-server
  ]) ++ (with pkgsUnstable; [
    # Bun runtime for the herdr-web-ui plugin's build/startup hooks (needs
    # >= 1.4; nixos-25.05 only has 1.2.x, unstable has 1.4.x). The plugin
    # also probes ~/.bun and Homebrew, but the Nix profile keeps activation
    # self-contained on both macOS and Linux hosts.
    bun
    gh
    go
    tokei
    tree-sitter
    ty
  ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin
    ((with pkgs; [ colima rar sketchybar terminal-notifier yabai ])
      ++ (with pkgsUnstable; [ macism ]))
    ++ lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin)
    ((with pkgs; [
      imagemagick
      emacs-pgtk
      fswatch
      # Parity with the macOS Homebrew casks: kitty/Doom main face,
      # doom-modeline's hardcoded "Symbols Nerd Font Mono" family, and
      # Doom's CJK fallback.
      nerd-fonts.iosevka
      nerd-fonts.symbols-only
      lxgw-wenkai
    ]));
}
