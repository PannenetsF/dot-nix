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
    gcc
    git-filter-repo
    gnuplot
    graphviz
    helix
    htop
    hugo
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
      ++ (with pkgsUnstable; [ macism ]));
}
