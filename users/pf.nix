{ config, pkgs, pkgsUnstable, ... }:

{
    imports = [./shared.nix];  
  home.username = "pf";
  home.homeDirectory = "/home/pf";

}
