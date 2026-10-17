{ config, pkgs, lib, ... }: {
  home.emptyActivationPath = false;
  home.activation.runMyScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Reference the flake source directory (not the file directly) so the
    # store path keeps install-linux-server.sh and its sourced sibling
    # install-common.sh co-located under <hash>-source/.
    bash ${../.}/install-linux-server.sh
    # Bootstrap Doom Emacs on Linux (emacs-pgtk from Nix profile is already
    # available at this point). Non-fatal — first activation may not have
    # network, and the script is idempotent.
    if command -v emacs >/dev/null 2>&1; then
      bash ${../.}/install-doom.sh || true
    fi
  '';
}
