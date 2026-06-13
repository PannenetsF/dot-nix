{ pkgs, username, ... }: {
  environment.systemPackages = [ pkgs.duti ];

  system.defaults.CustomUserPreferences = {
    "com.raycast.macos" = {
      onboardingCompleted = true;
      onboarding_setupAlias = true;
      onboarding_setupHotkey = true;
      raycastPreferredWindowMode = "compact";
      raycastShouldFollowSystemAppearance = true;
      showGettingStartedLink = false;
      useHyperKeyIcon = false;
    };

    "org.p0deje.Maccy" = {
      historySize = 200;
      pasteByDefault = true;
      popupPosition = "statusItem";
      removeFormattingByDefault = false;
      searchMode = "fuzzy";
      showInStatusBar = true;
    };

    "com.Snipaste" = { SUEnableAutomaticChecks = false; };
  };

  system.activationScripts.defaultApplications.text = ''
    # Default app handlers
    if command -v duti >/dev/null 2>&1; then
      echo >&2 "default applications..."
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- duti -s org.mozilla.firefox http all || true
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- duti -s org.mozilla.firefox https all || true
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- duti -s com.apple.Preview public.pdf all || true
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- duti -s com.microsoft.VSCode public.plain-text all || true
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- duti -s com.microsoft.VSCode public.source-code all || true
    fi
  '';
}
