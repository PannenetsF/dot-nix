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
    cmake
    docker
    gcc
    git-filter-repo
    gnuplot
    graphviz
    helix
    htop
    hugo
    ispell
    jq
    libgccjit
    libsodium
    lnav
    luarocks
    mermaid-cli
    neofetch
    ninja
    pandoc
    pkgconf
    poppler
    pythonEnv
    shfmt
    stylua
  ]) ++ (with pkgsUnstable; [ gh go tokei tree-sitter ty ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin
    ((with pkgs; [ colima rar sketchybar terminal-notifier yabai ])
      ++ (with pkgsUnstable; [ macism ]));
}
