{ homeDir, username, ... }: {
  system.defaults = {
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 12;
      KeyRepeat = 2;
      AppleKeyboardUIMode = 3;
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

    loginwindow.GuestEnabled = false;
  };

  system.activationScripts.ensureScreenshotDirectory.text = ''
    mkdir -p ${homeDir}/Pictures/Screenshots
    chown ${username}:staff ${homeDir}/Pictures ${homeDir}/Pictures/Screenshots 2>/dev/null || true
  '';
}
