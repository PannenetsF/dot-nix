{ pkgs, ... }: {
  # Desktop GUI apps live in brew/Brewfile so macOS indexes them as native
  # /Applications apps. Keep Nix here for fonts and assets used by the desktop.
  home.packages = with pkgs; [ nerd-fonts.shure-tech-mono sketchybar-app-font ];
}
