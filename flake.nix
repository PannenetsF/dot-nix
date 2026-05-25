{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }:
    let
      lib = nixpkgs.lib;
      mkHomeConfig = { system, isHost ? false, }:
        let
          nixpkgsConfig = { allowUnfree = true; };
          pkgs = import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
          };
          pkgsUnstable = import nixpkgs-unstable {
            inherit system;
            config = nixpkgsConfig;
          };
        in home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit pkgsUnstable;
            inherit system;
            inherit isHost;
          };

          modules = [ ./home.nix ];
        };
    in {
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
