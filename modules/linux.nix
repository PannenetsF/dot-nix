{ config, pkgs, lib, ... }: {
  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Reference the flake source directory (not the file directly) so the
    # store path keeps install-linux-server.sh and its sourced sibling
    # install-common.sh co-located under <hash>-source/.
    bash ${../.}/install-linux-server.sh
  '';
}
