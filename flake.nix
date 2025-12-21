{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, ... }:
    let
      system = "x86_64-linux";
      inherit (nixpkgs) lib;
      pkgs = import nixpkgs { inherit system; };
      pkgsUnstable = import nixpkgs-unstable { inherit system; };
    in {
      nixosConfigurations = {
        nixos = nixpkgs.lib.nixosSystem {
          modules = [
            ./configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.pf = ./users/pf.nix;
              home-manager.extraSpecialArgs = { pkgsUnstable = pkgsUnstable; };
              home-manager.backupCommand = "\${pkgs.trash-cli}/bin/trash";
            }
          ];
        };
      };
      dockerHomeConfigurations = {
        root = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { pkgsUnstable = pkgsUnstable; };

          modules = [ ./user/docker.nix ];
        };
      };
    };
}
