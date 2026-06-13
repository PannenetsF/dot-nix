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
      mkUserHome = system:
        let
          nixHmUser = builtins.getEnv "NIX_HM_USER";
          nixHmHome = builtins.getEnv "NIX_HM_HOME";
          sudoUser = builtins.getEnv "SUDO_USER";
          shellUser = builtins.getEnv "USER";
          envHome = builtins.getEnv "HOME";
          isDarwin = builtins.match ".*-darwin" system != null;
          username = if nixHmUser != "" then
            nixHmUser
          else if isDarwin && sudoUser != "" && sudoUser != "root" then
            sudoUser
          else
            shellUser;
          effectiveHome = if nixHmHome != "" then
            nixHmHome
          else if isDarwin && username != "root" && (envHome == "" || envHome
            == "/var/root" || shellUser == "root") then
            ""
          else
            envHome;
          inferredHome = if username == "" then
            ""
          else if isDarwin then
            "/Users/${username}"
          else if username == "root" then
            "/root"
          else
            "/home/${username}";
        in {
          inherit username;
          homeDir = if effectiveHome != "" then effectiveHome else inferredHome;
        };
      mkHomeConfig = { system, isHost ? false, }:
        let
          userHome = mkUserHome system;
          pkgs = mkPkgs system;
          pkgsUnstable = mkPkgsUnstable system;
        in home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit pkgsUnstable;
            inherit system;
            inherit isHost;
            inherit (userHome) username homeDir;
          };

          modules = [ ./home.nix ];
        };
      mkDarwinConfig = { system, }:
        let userHome = mkUserHome system;
        in nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit system;
            inherit (userHome) username homeDir;
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
