{ config, pkgs, pkgsUnstable, lib, ... }:
{
  imports =
    [ ./modules/common.nix ]
    ++ lib.optionals pkgs.stdenv.isLinux [ ./modules/linux.nix ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ ./modules/darwin.nix ];

  home = {
    username = builtins.getEnv "USER";
    homeDirectory = builtins.getEnv "HOME";
    stateVersion = "25.05";
  };
}
