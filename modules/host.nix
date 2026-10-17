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
    # Bun runtime for the herdr-web-ui plugin's build/startup hooks (needs
    # >= 1.4; its scripts also probe ~/.bun and Homebrew, but the Nix profile
    # keeps activation self-contained on both macOS and Linux hosts).
    bun
    cmake
    docker
    dockerfile-language-server-nodejs
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
    neofetch
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
  ]) ++ (with pkgsUnstable; [ gh go tokei tree-sitter ty ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin
    ((with pkgs; [ colima rar sketchybar terminal-notifier yabai ])
      ++ (with pkgsUnstable; [ macism ]))
    ++ lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin)
    ((with pkgs; [ imagemagick emacs-pgtk ]));
}
