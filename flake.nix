{
  description = "My Home Manager configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Last nixpkgs release that still ships an x86_64-darwin stdenv. nixpkgs
    # 26.11/unstable removed the Intel Darwin bootstrap entirely (the Darwin
    # stdenv throws unconditionally), so the personal Herdr source build for
    # x86_64-darwin — which has no published release asset — is built here,
    # where zig_0_16.fetchDeps is also available. Used only for that target.
    nixpkgs-26_05.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nixpkgs-26_05, home-manager
    , nix-darwin, ... }:
    let
      lib = nixpkgs.lib;
      darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      # nixpkgs-unstable (26.11) hard-throws on x86_64-darwin and also lists it
      # as an unsupported platform; this repo still declares that target, so opt
      # back in with both documented escape hatches. The personal Herdr package
      # on every target except x86_64-darwin is built against this set. Ignored
      # by the nixos-25.05 package set, where the keys do not gate this
      # platform.
      nixpkgsConfig = {
        allowUnfree = true;
        allowDeprecatedx86_64Darwin = "force";
        allowUnsupportedSystem = true;
      };
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
      # x86_64-darwin still has a supported (if deprecated) stdenv on 26.05, so
      # no allowUnsupportedSystem escape hatch is needed there.
      mkPkgs2605 = system:
        import nixpkgs-26_05 {
          inherit system;
          config = { allowUnfree = true; };
        };
      # Personal TRAE-enabled Herdr (PannenetsF/herdr fork). The package picks a
      # published release binary or a source build per system inside pkgs/herdr.
      # x86_64-darwin has no release asset and unstable deleted its stdenv, so
      # only that target's source build uses nixos-26.05 (zig_0_16 present,
      # agent-skills hook vendored); all other targets use nixpkgs-unstable,
      # which the source build otherwise needs for zig_0_16.fetchDeps.
      mkHerdr = system:
        let
          herdrPkgs = if system == "x86_64-darwin" then
            mkPkgs2605 system
          else
            mkPkgsUnstable system;
        in herdrPkgs.callPackage ./pkgs/herdr { };
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
      mkHomeConfig = { system, isHost ? false, isDocker ? false, }:
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
            inherit isDocker;
            herdrPkg = mkHerdr system;
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
            herdrPkg = mkHerdr system;
          };
          modules = [
            ./nix-darwin/configuration.nix
            home-manager.darwinModules.home-manager
          ];
        };
    in {
      packages = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: { herdr = mkHerdr system; });

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
        "x86_64-linux-docker" = mkHomeConfig {
          system = "x86_64-linux";
          isDocker = true;
        };
        "aarch64-linux-docker" = mkHomeConfig {
          system = "aarch64-linux";
          isDocker = true;
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
