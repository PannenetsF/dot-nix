{ config, pkgs, pkgsUnstable, lib, ... }:
{
  imports =
    [ ./modules/common.nix ]
    ++ (
      if builtins.match ".*-linux" builtins.currentSystem != null then
        [ ./modules/linux.nix ]
      else
        [ ]
    )
    ++ (
      if builtins.match ".*-darwin" builtins.currentSystem != null then
        [ ./modules/darwin.nix ]
      else
        [ ]
    );

  home = {
    username = builtins.getEnv "USER";
    homeDirectory = builtins.getEnv "HOME";
    stateVersion = "25.05";
  };
}
