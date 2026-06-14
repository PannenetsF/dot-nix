{ config, lib, username, ... }:
let brewBin = "${config.homebrew.brewPrefix}/brew";
in {
  system.activationScripts.preActivation.text = lib.mkAfter ''
    if [ -x "${brewBin}" ]; then
      echo >&2 "trusting WhatPulse Homebrew tap..."
      launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
        env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" trust --tap whatpulse/whatpulse --quiet
    fi
  '';

  homebrew = {
    enable = true;

    taps = [ "daipeihust/tap" "gromgit/fuse" "whatpulse/whatpulse" ];

    casks = [
      "1password"
      "chatgpt"
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
      "nutstore"
      "nvidia-nsight-compute"
      "nvidia-nsight-systems"
      "obsidian"
      "raycast"
      "scroll-reverser"
      "sf-symbols"
      "skim"
      "snipaste"
      "tencent-lemon"
      "visual-studio-code"
      "wechat"
      "whatpulse/whatpulse/whatpulse"
      "zed"
      "zotero"
    ];

    brews = [ "daipeihust/tap/im-select" "gromgit/fuse/sshfs-mac" ];

    global = {
      autoUpdate = false;
      brewfile = true;
    };

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };
}
