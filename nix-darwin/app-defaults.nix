{ lib, pkgs, username, ... }: {
  environment.systemPackages = [ pkgs.duti ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    write_user_default() {
      launchctl asuser "$(id -u ${username})" sudo --user=${username} -- defaults write "$@"
    }

    echo >&2 "app defaults..."
    write_user_default com.raycast.macos onboardingCompleted -bool true
    write_user_default com.raycast.macos onboarding_setupAlias -bool true
    write_user_default com.raycast.macos onboarding_setupHotkey -bool true
    write_user_default com.raycast.macos raycastPreferredWindowMode -string compact
    write_user_default com.raycast.macos raycastShouldFollowSystemAppearance -bool true
    write_user_default com.raycast.macos showGettingStartedLink -bool false
    write_user_default com.raycast.macos useHyperKeyIcon -bool false

    write_user_default org.p0deje.Maccy historySize -int 200
    write_user_default org.p0deje.Maccy pasteByDefault -bool true
    write_user_default org.p0deje.Maccy popupPosition -string statusItem
    write_user_default org.p0deje.Maccy removeFormattingByDefault -bool false
    write_user_default org.p0deje.Maccy searchMode -string fuzzy
    write_user_default org.p0deje.Maccy showInStatusBar -bool true

    write_user_default com.Snipaste SUEnableAutomaticChecks -bool false

    # Default app handlers
    if command -v duti >/dev/null 2>&1; then
      echo >&2 "default applications..."
      launchctl asuser "$(id -u ${username})" sudo -u ${username} duti -s org.mozilla.firefox http all || true
      launchctl asuser "$(id -u ${username})" sudo -u ${username} duti -s org.mozilla.firefox https all || true
      launchctl asuser "$(id -u ${username})" sudo -u ${username} duti -s com.apple.Preview public.pdf all || true
      launchctl asuser "$(id -u ${username})" sudo -u ${username} duti -s com.microsoft.VSCode public.plain-text all || true
      launchctl asuser "$(id -u ${username})" sudo -u ${username} duti -s com.microsoft.VSCode public.source-code all || true
    fi
  '';
}
