{
  pkgs,
  pkgsUnstable,
  ...
}:
{
  home.packages =
    (with pkgs; [
      _1password-gui
      brave
      inkscape
      karabiner-elements
      keycastr
      monitorcontrol
      nerd-fonts.shure-tech-mono
      sketchybar-app-font
      skim
      zotero
    ])
    ++ (with pkgsUnstable; [
      firefox
      kitty
      maccy
      obsidian
      raycast
      scroll-reverser
      vscode
      wechat
      zed-editor
    ]);
}
