{ config, pkgs, pkgsUnstable, lib, system, ... }:
{
  imports =
    [ ./modules/common.nix ]
    ++ (
      if builtins.match ".*-linux" system != null then
        [ ./modules/linux.nix ]
      else
        [ ]
    )
    ++ (
      if builtins.match ".*-darwin" system != null then
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
