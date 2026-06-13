{ pkgs, ... }: {
  # Desktop GUI apps live in nix-darwin/homebrew.nix so macOS indexes them as
  # native /Applications apps. Keep Nix here for fonts and desktop assets.
  home.packages = with pkgs; [ nerd-fonts.shure-tech-mono sketchybar-app-font ];
}
