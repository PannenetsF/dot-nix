{
  pkgs,
  pkgsUnstable,
  lib,
  ...
}:
{
  home.packages =
    (with pkgs; [
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
      python3
      shfmt
      stylua
    ])
    ++ (with pkgsUnstable; [
      gh
      go
      tokei
      tree-sitter
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin (
      (with pkgs; [
        colima
        rar
        sketchybar
        terminal-notifier
        yabai
      ])
      ++ (with pkgsUnstable; [
        macism
      ])
    );
}
