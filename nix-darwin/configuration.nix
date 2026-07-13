{ pkgsUnstable, system, username, homeDir, ... }: {
  imports = [
    ./app-defaults.nix
    ./gui-apps.nix
    ./homebrew.nix
    ./macos-defaults.nix
  ];

  system.stateVersion = 6;
  system.primaryUser = username;

  users.users.${username}.home = homeDir;

  # Determinate Nix Installer manages the Nix daemon itself. Let it own the Nix
  # installation so nix-darwin does not conflict with Determinate's daemon.
  nix.enable = false;
  nixpkgs.config.allowUnfree = true;

  # Use Touch ID for sudo on local interactive sessions. Reattach keeps the
  # prompt working from terminal multiplexers such as tmux and screen.
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  # Home Manager owns the user zsh setup and oh-my-zsh already initializes
  # completion. Avoid a second system-wide compinit from /etc/zshrc.
  programs.zsh.enableCompletion = false;
  programs.zsh.enableBashCompletion = false;

  services.openssh.enable = true;
  networking.wakeOnLan.enable = true;

  system.activationScripts.acPowerSshAvailability.text = ''
    echo "configuring AC power SSH availability..." >&2
    pmset -c sleep 0 displaysleep 0 disksleep 0 womp 1 tcpkeepalive 1 ttyskeepawake 1 standby 0 powernap 1
  '';

  launchd.daemons.acPowerCaffeinate = {
    command = "/usr/bin/caffeinate -s";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  system.activationScripts.remoteManagementCurtainMode.text = ''
    echo "configuring Remote Management for curtain mode..." >&2
    defaults write /Library/Preferences/com.apple.RemoteManagement ARD_AllLocalUsers -bool false
    defaults write /Library/Preferences/com.apple.RemoteManagement ARD_AllLocalUsersPrivs -int 0
    defaults write /Library/Preferences/com.apple.RemoteManagement LoadRemoteManagementMenuExtra -bool false
    defaults write /Library/Preferences/com.apple.RemoteManagement ScreenSharingReqPermEnabled -bool false
    defaults write /Library/Preferences/com.apple.RemoteManagement VNCLegacyConnectionsEnabled -bool false
    dscl . -create /Users/${username} naprivs -1073741569
    launchctl enable system/com.apple.screensharing
    launchctl load -wF /System/Library/LaunchDaemons/com.apple.screensharing.plist >/dev/null 2>&1 || true
    launchctl kickstart -k system/com.apple.screensharing >/dev/null 2>&1 || true
  '';

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit pkgsUnstable system username homeDir;
      isHost = true;
    };
    users.${username} = import ../home.nix;
  };
}
