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

  # Home Manager owns the user zsh setup and oh-my-zsh already initializes
  # completion. Avoid a second system-wide compinit from /etc/zshrc.
  programs.zsh.enableCompletion = false;
  programs.zsh.enableBashCompletion = false;

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
