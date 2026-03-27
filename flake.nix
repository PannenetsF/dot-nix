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

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      ...
    }:
    let
      lib = nixpkgs.lib;
      mkHomeConfig = system:
        let
          pkgs = import nixpkgs { inherit system; };
          pkgsUnstable = import nixpkgs-unstable { inherit system; };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit pkgsUnstable;
          };

          modules = [ ./home.nix ];
        };
    in
  {
    homeConfigurations = {
      "x86_64-linux" = mkHomeConfig "x86_64-linux";
      "aarch64-linux" = mkHomeConfig "aarch64-linux";
      "x86_64-darwin" = mkHomeConfig "x86_64-darwin";
      "aarch64-darwin" = mkHomeConfig "aarch64-darwin";
    };
  };
}
