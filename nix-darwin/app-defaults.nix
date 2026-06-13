{ lib, pkgs, username, homeDir, ... }: {
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

    maccy_plist="${homeDir}/Library/Preferences/org.p0deje.Maccy.plist"
    install -d -o ${username} -g staff "${homeDir}/Library/Preferences"
    if [ ! -e "$maccy_plist" ]; then
      printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
        '<plist version="1.0"><dict/></plist>' > "$maccy_plist"
    fi
    set_maccy_default() {
      key="$1"
      type="$2"
      value="$3"
      /usr/libexec/PlistBuddy -c "Set :$key $value" "$maccy_plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$maccy_plist"
    }
    set_maccy_default historySize integer 200
    set_maccy_default pasteByDefault bool true
    set_maccy_default popupPosition string statusItem
    set_maccy_default removeFormattingByDefault bool false
    set_maccy_default searchMode string fuzzy
    set_maccy_default showInStatusBar bool true
    chown ${username}:staff "$maccy_plist"
    launchctl asuser "$(id -u ${username})" sudo --user=${username} -- killall cfprefsd 2>/dev/null || true

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
