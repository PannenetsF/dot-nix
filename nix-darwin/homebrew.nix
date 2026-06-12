{
  homebrew = {
    enable = true;

    taps = [ "daipeihust/tap" "gromgit/fuse" ];

    casks = [
      "1password"
      "firefox"
      "font-sf-pro"
      "input-source-pro"
      "karabiner-elements"
      "keycastr"
      "kitty"
      "macfuse"
      "maccy"
      "monitorcontrol"
      "neteasemusic"
      "obsidian"
      "raycast"
      "scroll-reverser"
      "sf-symbols"
      "skim"
      "snipaste"
      "tencent-lemon"
      "visual-studio-code"
      "wechat"
      "zed"
      "zotero"
    ];

    brews = [ "daipeihust/tap/im-select" "gromgit/fuse/sshfs-mac" ];

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };

    global = {
      autoUpdate = false;
      brewfile = true;
    };
  };
}
