{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nix-darwin, ... }:
    let
      lib = nixpkgs.lib;
      darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      nixpkgsConfig = { allowUnfree = true; };
      mkPkgs = system:
        import nixpkgs {
          inherit system;
          config = nixpkgsConfig;
        };
      mkPkgsUnstable = system:
        import nixpkgs-unstable {
          inherit system;
          config = nixpkgsConfig;
        };
      mkHomeConfig = { system, isHost ? false, }:
        let
          pkgs = mkPkgs system;
          pkgsUnstable = mkPkgsUnstable system;
        in home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit pkgsUnstable;
            inherit system;
            inherit isHost;
          };

          modules = [ ./home.nix ];
        };
      mkDarwinConfig = { system, }:
        let
          nixHmUser = builtins.getEnv "NIX_HM_USER";
          nixHmHome = builtins.getEnv "NIX_HM_HOME";
          sudoUser = builtins.getEnv "SUDO_USER";
          userEnv = builtins.getEnv "USER";
          homeEnv = builtins.getEnv "HOME";
          username = if nixHmUser != "" then
            nixHmUser
          else if sudoUser != "" && sudoUser != "root" then
            sudoUser
          else if userEnv != "" then
            userEnv
          else
            throw
            "Unable to determine Darwin username; set NIX_HM_USER or USER";
          homeDir = if nixHmHome != "" then
            nixHmHome
          else if username != "root"
          && (homeEnv == "" || homeEnv == "/var/root" || userEnv == "root") then
            "/Users/${username}"
          else if homeEnv != "" then
            homeEnv
          else if username == "root" then
            "/var/root"
          else
            "/Users/${username}";
        in nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit system username homeDir;
            pkgsUnstable = mkPkgsUnstable system;
          };
          modules = [
            ./nix-darwin/configuration.nix
            home-manager.darwinModules.home-manager
          ];
        };
    in {
      apps = lib.genAttrs darwinSystems (system: {
        darwin-rebuild = {
          type = "app";
          program = "${
              nix-darwin.packages.${system}.darwin-rebuild
            }/bin/darwin-rebuild";
        };
      });

      darwinConfigurations = {
        "x86_64-darwin" = mkDarwinConfig { system = "x86_64-darwin"; };
        "aarch64-darwin" = mkDarwinConfig { system = "aarch64-darwin"; };
      };

      homeConfigurations = {
        "x86_64-linux" = mkHomeConfig { system = "x86_64-linux"; };
        "aarch64-linux" = mkHomeConfig { system = "aarch64-linux"; };
        "x86_64-linux-host" = mkHomeConfig {
          system = "x86_64-linux";
          isHost = true;
        };
        "aarch64-linux-host" = mkHomeConfig {
          system = "aarch64-linux";
          isHost = true;
        };
        "x86_64-darwin" = mkHomeConfig {
          system = "x86_64-darwin";
          isHost = true;
        };
        "aarch64-darwin" = mkHomeConfig {
          system = "aarch64-darwin";
          isHost = true;
        };
      };
    };
}
