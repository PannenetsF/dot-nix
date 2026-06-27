{ config, homeDir, lib, username, ... }:
let
  brewBin = "${config.homebrew.brewPrefix}/brew";
  localTapPath = "${homeDir}/.cache/dot-nix/homebrew-local-tap";
in {
  system.activationScripts.preActivation.text = lib.mkAfter ''
        if [ -x "${brewBin}" ]; then
          echo >&2 "preparing local Homebrew tap..."
          install -d -o ${username} -g staff "${localTapPath}/Casks"

          cat > "${localTapPath}/Casks/whatpulse-chmodbpf.rb" <<'RUBY'
    cask "whatpulse-chmodbpf" do
      version "1.0"
      sha256 "739fe63afe689b19de5df1b391ff702fc39f350348c0d05661432bb742e49483"

      url "https://releases.whatpulse.org/latest/macos/install.ChmodBPF.pkg"
      name "WhatPulse ChmodBPF"
      desc "ChmodBPF package required for WhatPulse network stats"
      homepage "https://whatpulse.org"

      pkg "install.ChmodBPF.pkg"
    end
    RUBY

          cat > "${localTapPath}/Casks/whatpulse.rb" <<'RUBY'
    cask "whatpulse" do
      version "6.2.1"
      sha256 :no_check

      url "https://releases.whatpulse.org/latest/macos-arm/whatpulse-mac-arm-latest.dmg",
          verified: "releases.whatpulse.org/latest/macos-arm/"
      name "WhatPulse"
      desc "Activity and productivity tracker"
      homepage "https://whatpulse.org"

      installer script: {
        executable: "/bin/bash",
        args: [
          "-c",
          "MAINTENANCE_TOOL='/Applications/WhatPulse/WhatPulseMaintenanceTool.app/Contents/MacOS/WhatPulseMaintenanceTool'; " \
          'if [ -x "$MAINTENANCE_TOOL" ]; then ' \
          '"$MAINTENANCE_TOOL" update --accept-licenses --default-answer --confirm-command; ' \
          'RC=$?; if [ $RC -eq 0 ] || [ $RC -eq 3 ]; then exit 0; else exit $RC; fi; ' \
          'else ' \
          "\"#{staged_path}/WhatPulse-#{version}-Installer.app/Contents/MacOS/WhatPulse-#{version}-Installer\" " \
          '--root /Applications/WhatPulse --accept-messages --accept-licenses --confirm-command ' \
          "--cache-path \"#{staged_path}/cache\" install; " \
          'fi'
        ]
      }

      uninstall script: {
        executable: "/Applications/WhatPulse/WhatPulseMaintenanceTool.app/Contents/MacOS/WhatPulseMaintenanceTool",
        args: ["--confirm-command", "remove", "com.whatpulse.client", "com.whatpulse.maintenancetool"]
      },
      delete: "/Applications/WhatPulse"
    end
    RUBY

          chown -R ${username}:staff "${localTapPath}"
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" init -q
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" config user.name "dot-nix"
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" config user.email "dot-nix@example.invalid"
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" add Casks
          if ! launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" diff --cached --quiet; then
            launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
              /usr/bin/git -C "${localTapPath}" commit -q -m "Update local casks"
          fi
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" tap dot-nix/local "${localTapPath}"
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" trust dot-nix/local --quiet
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" tap nikitabobko/tap
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" trust nikitabobko/tap --quiet
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" untap whatpulse/whatpulse || true
        fi
  '';

  homebrew = {
    enable = true;

    taps = [
      "daipeihust/tap"
      "gromgit/fuse"
      "nikitabobko/tap"
      {
        name = "dot-nix/local";
        clone_target = localTapPath;
      }
    ];

    casks = [
      "1password"
      "nikitabobko/tap/aerospace"
      "chatgpt"
      "cc-switch"
      "codex"
      "firefox"
      "font-ubuntu-mono-nerd-font"
      "font-ubuntu-nerd-font"
      "font-sf-pro"
      "input-source-pro"
      "karabiner-elements"
      "keycastr"
      "kitty"
      "macfuse"
      "maccy"
      "microsoft-edge"
      "monitorcontrol"
      "neovide-app"
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
      "dot-nix/local/whatpulse-chmodbpf"
      "dot-nix/local/whatpulse"
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
