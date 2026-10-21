{ config, homeDir, lib, username, ... }:
let
  brewBin = "${config.homebrew.brewPrefix}/brew";
  localTapPath = "${homeDir}/.cache/dot-nix/homebrew-local-tap";
  herdiCask = ../config/homebrew/Casks/herdi.rb;
in {
  system.activationScripts.preActivation.text = lib.mkAfter ''
        if [ -x "${brewBin}" ]; then
          echo >&2 "preparing local Homebrew tap..."
          install -d -o ${username} -g staff "${localTapPath}/Casks"
          install -m 0644 "${herdiCask}" \
            "${localTapPath}/Casks/herdi.rb"

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

          # WhatPulse ships separate ARM and Intel "latest" DMGs, so choose the
          # URL for this Mac's arch at activation time. Both URLs were verified
          # to serve application/x-apple-diskimage (HTTP 200) via curl -sIL.
          case "$(uname -m)" in
            arm64)
              whatpulse_url="https://releases.whatpulse.org/latest/macos-arm/whatpulse-mac-arm-latest.dmg"
              ;;
            x86_64)
              whatpulse_url="https://releases.whatpulse.org/latest/macos/whatpulse-mac-latest.dmg"
              ;;
            *)
              # Unknown arch: the Intel build is the historical default and
              # degrades more safely than an ARM image on non-ARM hardware.
              whatpulse_url="https://releases.whatpulse.org/latest/macos/whatpulse-mac-latest.dmg"
              ;;
          esac

          # The delimiter is intentionally unquoted so $whatpulse_url expands;
          # every other "$" and continuation backslash in the Ruby body is
          # escaped for the shell. $whatpulse_url stays brace-free on purpose:
          # this text is a Nix indented string, where a dollar immediately
          # followed by "{" is Nix antiquotation.
          cat > "${localTapPath}/Casks/whatpulse.rb" <<RUBY
    cask "whatpulse" do
      version "6.2.1"
      sha256 :no_check

      url "$whatpulse_url"
      name "WhatPulse"
      desc "Activity and productivity tracker"
      homepage "https://whatpulse.org"

      installer script: {
        executable: "/bin/bash",
        args: [
          "-c",
          "MAINTENANCE_TOOL='/Applications/WhatPulse/WhatPulseMaintenanceTool.app/Contents/MacOS/WhatPulseMaintenanceTool'; " \\
          'if [ -x "\$MAINTENANCE_TOOL" ]; then ' \\
          '"\$MAINTENANCE_TOOL" update --accept-licenses --default-answer --confirm-command; ' \\
          'RC=\$?; if [ \$RC -eq 0 ] || [ \$RC -eq 3 ]; then exit 0; else exit \$RC; fi; ' \\
          'else ' \\
          "\"#{staged_path}/WhatPulse-#{version}-Installer.app/Contents/MacOS/WhatPulse-#{version}-Installer\" " \\
          '--root /Applications/WhatPulse --accept-messages --accept-licenses --confirm-command ' \\
          "--cache-path \"#{staged_path}/cache\" install; " \\
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

          brew_as_user tap furkankly/tap
          brew_as_user trust furkankly/tap --quiet

          # Homebrew 4.4+ refuses formulae from newly added third-party taps
          # until explicitly trusted; emacs-plus exists only in this tap.
          brew_as_user tap d12frosted/emacs-plus
          brew_as_user trust d12frosted/emacs-plus --quiet

          # AeroSpace/JankyBorders are retired (see
          # deprecated/00-aerospace-indicator/). Their installed casks/formulae
          # are left on disk for manual rollback; only the stale taps go.
          brew_as_user untap nikitabobko/tap || true
          brew_as_user untap felixkratz/formulae || true
          brew_as_user untap whatpulse/whatpulse || true
        fi
  '';

  homebrew = {
    enable = true;

    taps = [
      "d12frosted/emacs-plus"
      "daipeihust/tap"
      "furkankly/tap"
      "gromgit/fuse"
      {
        name = "dot-nix/local";
        clone_target = localTapPath;
      }
    ];

    # OmniWM is the managed window manager; it uses the official signed/
    # notarized stable cask, not canaries. The retired AeroSpace cask and
    # JankyBorders formula live on in deprecated/00-aerospace-indicator/.
    casks = [
      "1password"
      "chatgpt"
      "cc-switch"
      "claude"
      "claude-code"
      "codex"
      "codex-app"
      "firefox"
      # Fonts must come from casks: nix nerd-fonts packages land in the
      # nix store and are never registered with CoreText, so neither
      # kitty nor Emacs can see them. Iosevka NF is kitty's font_family
      # (config/kitty/kitty.conf) and Doom's doom-font (dot-doom
      # config.el); LXGW WenKai Mono is Doom's CJK fallback face.
      "font-iosevka-nerd-font"
      "font-lxgw-wenkai"
      # nerd-icons/doom-modeline render icons with the family hardcoded
      # to "Symbols Nerd Font Mono" (no fallback to the default face when
      # use-default-font-for-symbols is nil); without this cask every
      # modeline icon shows as a hex tofu box. kitty also auto-uses it as
      # the PUA symbol_map fallback.
      "font-symbols-only-nerd-font"
      "font-ubuntu-mono-nerd-font"
      "font-sf-pro"
      # herdr-remote menu-bar client; ad-hoc signed and unnotarized, so the
      # first launch needs a right-click -> Open (see config/homebrew/Casks/herdi.rb).
      "dot-nix/local/herdi"
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
      # Skim used to pass `args: { no_quarantine = true; }` because, as the
      # default PDF handler, opening a file through LaunchServices triggered a
      # Gatekeeper prompt. Homebrew 7 removed --no-quarantine entirely (commit
      # ba25213c81), so the arg now makes fresh installs fail with "invalid
      # option". Notarized .app casks prompt only once and Homebrew 7 inherits
      # that approval across upgrades when the signer is unchanged; a
      # TCC-protected .app bundle cannot be unquarantined from activation
      # anyway (xattr removal is EPERM even for root).
      "skim"
      "snipaste"
      "tencent-lemon"
      "telegram"
      "visual-studio-code"
      "wechat"
      "dot-nix/local/whatpulse-chmodbpf"
      "dot-nix/local/whatpulse"
      "zed"
      "zotero"
      "omniwm"
    ];

    brews = [
      "daipeihust/tap/im-select"
      # Emacs for Doom — emacs-plus on macOS gives native Cocoa GUI
      # with compile-time options (modern icon, imagemagick, mailutils)
      # that nixpkgs emacs-pgtk (GTK3/X11 on macOS) cannot match. The
      # formula only exists in the d12frosted/emacs-plus tap (declared
      # above), so it must stay fully-qualified here.
      "d12frosted/emacs-plus/emacs-plus"
      "furkankly/tap/zoetrope"
      # vulpea (Doom org-roam) prefers fswatch for file change events and
      # otherwise falls back to polling with a startup message.
      "fswatch"
      "gromgit/fuse/sshfs-mac"
      "herdr"
      # Native backend for Doom's :input chinese +rime (liberime links
      # -lrime and finds headers via pkg-config; dot-doom compiles the
      # liberime emacs module on demand, see ~/.config/doom/config.el).
      "librime"
      "pkgconf"
    ];

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

  # postActivation slots run after nix-darwin's `brew bundle` step, so strip
  # quarantine from the unnotarized bare-binary casks immediately after a new
  # version lands (and after a first install). Runs as the user, who owns the
  # Caskroom; must never break activation.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    if [ -x "${brewBin}" ]; then
      launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
        env BREW_BIN="${brewBin}" PATH="${config.homebrew.brewPrefix}:/usr/bin:/bin" \
        bash "${../brew/unquarantine-casks.sh}" || true
      # Bootstrap Doom Emacs after brew bundle (emacs-plus must be
      # installed first). Runs as the user so ~/.config/doom and
      # ~/.config/emacs are owned correctly.
      if launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
        env PATH="${config.homebrew.brewPrefix}:/usr/bin:/bin" \
        emacs --batch --version >/dev/null 2>&1; then
        launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
          env PATH="${config.homebrew.brewPrefix}:/usr/bin:/bin" \
          bash "${../.}/install-doom.sh" || true
      fi
    fi
  '';
}
