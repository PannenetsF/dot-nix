{ pkgsUnstable, system, username, homeDir, ... }: {
  system.stateVersion = 6;
  system.primaryUser = username;

  users.users.${username}.home = homeDir;

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit pkgsUnstable system;
      isHost = true;
    };
    users.${username} = import ../home.nix;
  };
}
