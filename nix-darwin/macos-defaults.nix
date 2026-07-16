{ homeDir, username, ... }: {
  system.defaults = {
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 12;
      KeyRepeat = 2;
      AppleKeyboardUIMode = 3;
      "com.apple.keyboard.fnState" = true;
      AppleShowAllExtensions = true;
      AppleShowScrollBars = "Automatic";
      AppleSpacesSwitchOnActivate = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticWindowAnimationsEnabled = false;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;
      _HIHideMenuBar = true;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.forceClick" = false;
      "com.apple.trackpad.scaling" = 2.0;
    };

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      expose-animation-duration = 0.1;
      expose-group-apps = true;
      launchanim = false;
      mineffect = "scale";
      minimize-to-application = true;
      mru-spaces = false;
      orientation = "bottom";
      show-recents = false;
      tilesize = 36;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      NewWindowTarget = "Home";
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      _FXSortFoldersFirst = true;
    };

    trackpad = {
      Clicking = true;
      Dragging = true;
      TrackpadRightClick = true;
    };

    screencapture = {
      location = "${homeDir}/Pictures/Screenshots";
      type = "png";
      disable-shadow = true;
    };

    controlcenter = {
      Sound = true;
      NowPlaying = false;
    };

    CustomUserPreferences = {
      "com.apple.controlcenter" = {
        "NSStatusItem VisibleCC AudioVideoModule" = true;
        "NSStatusItem VisibleCC NowPlaying" = false;
      };

      "com.apple.Spotlight" = {
        "NSStatusItem VisibleCC Item-0" = false;
      };

      "com.apple.spaces" = {
        spans-displays = true;
      };
    };

    loginwindow.GuestEnabled = false;
  };

  system.activationScripts.ensureScreenshotDirectory.text = ''
    mkdir -p ${homeDir}/Pictures/Screenshots
    chown ${username}:staff ${homeDir}/Pictures ${homeDir}/Pictures/Screenshots 2>/dev/null || true
  '';

  system.activationScripts.refreshFunctionKeyMode.text = ''
    /usr/bin/defaults write ${homeDir}/Library/Preferences/.GlobalPreferences com.apple.keyboard.fnState -bool true
    chown ${username}:staff ${homeDir}/Library/Preferences/.GlobalPreferences.plist 2>/dev/null || true

    user_uid="$(id -u ${username} 2>/dev/null || true)"
    if [ -n "$user_uid" ]; then
      for label in \
        org.pqrs.service.agent.Karabiner-Core-Service-rev2 \
        org.pqrs.service.agent.karabiner_console_user_server \
        org.pqrs.service.agent.Karabiner-Menu \
        org.pqrs.service.agent.Karabiner-NotificationWindow; do
        launchctl asuser "$user_uid" launchctl kickstart -k "gui/$user_uid/$label" 2>/dev/null || true
      done
    fi
  '';
}
