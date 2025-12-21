{ config, pkgs, pkgsUnstable, lib, ... }: {
  home.username = "root";
  home.homeDirectory = "/root";
  home.sessionVariables = { PATH = "$HOME/.local/bin:$PATH"; };

  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    bash ~/.config/nix-hm/install-linux-server.sh
  '';

}
