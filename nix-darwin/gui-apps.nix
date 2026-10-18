{ config, lib, pkgs, ... }: {
  # GUI helpers suitable for Nix installation. The retired tiling-WM stack
  # (renderer, workspace indicator, focused-window border daemon) is archived
  # under deprecated/00-aerospace-indicator/; OmniWM replaces it.
  environment.systemPackages = with pkgs; [
    nerd-fonts.iosevka
    nerd-fonts.shure-tech-mono
    sketchybar-app-font
  ];
}
