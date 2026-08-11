{ config, homeDir, lib, username, ... }:
let
  brewBin = "${config.homebrew.brewPrefix}/brew";
  localTapPath = "${homeDir}/.cache/dot-nix/homebrew-local-tap";
  aerospacePatchedCask = ../config/homebrew/Casks/aerospace-patched.rb;
  aerospacePatchedVersion = "0.21.3-Beta-pf.1";
in {
  system.activationScripts.preActivation.text = lib.mkAfter ''
        if [ -x "${brewBin}" ]; then
          echo >&2 "preparing local Homebrew tap..."
          install -d -o ${username} -g staff "${localTapPath}/Casks"
          install -m 0644 "${aerospacePatchedCask}" \
            "${localTapPath}/Casks/aerospace-patched.rb"

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
          # Keep the source tap's branch deterministic. Homebrew's installed
          # checkout pulls this branch explicitly below, while older Git
          # installations may otherwise initialize new repositories as master.
          if launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "${localTapPath}" rev-parse --verify HEAD >/dev/null 2>&1; then
            launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
              /usr/bin/git -C "${localTapPath}" branch -M main
          else
            launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
              /usr/bin/git -C "${localTapPath}" symbolic-ref HEAD refs/heads/main
          fi
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

          brew_as_user() {
            launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
              env HOMEBREW_NO_AUTO_UPDATE=1 "${brewBin}" "$@"
          }

          brew_as_user tap dot-nix/local "${localTapPath}"
          tap_checkout="$(brew_as_user --repository dot-nix/local)"
          launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
            /usr/bin/git -C "$tap_checkout" pull --ff-only -q origin main
          brew_as_user trust dot-nix/local --quiet

          # Fetch and verify both the replacement and rollback artifact before
          # removing the upstream cask. If installation still fails, make the
          # rollback result explicit rather than hiding a second failure.
          if brew_as_user list --cask --versions aerospace >/dev/null 2>&1; then
            echo >&2 "migrating AeroSpace to dot-nix/local/aerospace-patched..."
            if ! brew_as_user fetch --cask dot-nix/local/aerospace-patched; then
              echo >&2 "failed to fetch patched AeroSpace; keeping the upstream cask"
              exit 1
            fi
            if ! brew_as_user fetch --cask nikitabobko/tap/aerospace; then
              echo >&2 "failed to cache the upstream AeroSpace rollback; keeping the upstream cask"
              exit 1
            fi
            if ! brew_as_user uninstall --cask --force nikitabobko/tap/aerospace; then
              echo >&2 "failed to uninstall the upstream AeroSpace cask"
              exit 1
            fi
            if ! brew_as_user install --cask dot-nix/local/aerospace-patched; then
              echo >&2 "failed to install patched AeroSpace; restoring the upstream cask"
              brew_as_user uninstall --cask --force aerospace-patched >/dev/null 2>&1 || true
              if ! brew_as_user tap nikitabobko/tap; then
                echo >&2 "warning: could not re-add nikitabobko/tap during rollback"
              fi
              if ! brew_as_user trust nikitabobko/tap --quiet; then
                echo >&2 "warning: could not re-trust nikitabobko/tap during rollback"
              fi
              if ! brew_as_user install --cask nikitabobko/tap/aerospace; then
                echo >&2 "warning: upstream AeroSpace reinstall command failed"
              fi
              if brew_as_user list --cask --versions aerospace >/dev/null 2>&1; then
                echo >&2 "restored the upstream AeroSpace cask"
              else
                echo >&2 "CRITICAL: failed to restore upstream AeroSpace; reinstall nikitabobko/tap/aerospace manually"
              fi
              exit 1
            fi
          fi

          installed_patched_version="$(
            brew_as_user list --cask --versions aerospace-patched 2>/dev/null \
              | /usr/bin/awk '{print $2}' || true
          )"
          if [ -n "$installed_patched_version" ] && \
             [ "$installed_patched_version" != "${aerospacePatchedVersion}" ]; then
            echo >&2 "upgrading patched AeroSpace to ${aerospacePatchedVersion}..."
            brew_as_user fetch --cask dot-nix/local/aerospace-patched
            brew_as_user upgrade --cask dot-nix/local/aerospace-patched
          fi

          brew_as_user untap nikitabobko/tap || true
          brew_as_user untap whatpulse/whatpulse || true
        fi
  '';

  homebrew = {
    enable = true;

    taps = [
      "daipeihust/tap"
      "gromgit/fuse"
      {
        name = "dot-nix/local";
        clone_target = localTapPath;
      }
    ];

    casks = [
      "1password"
      "dot-nix/local/aerospace-patched"
      "chatgpt"
      "cc-switch"
      "claude"
      "claude-code"
      "codex"
      "codex-app"
      "firefox"
      "font-ubuntu-mono-nerd-font"
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
