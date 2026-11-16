{ config, lib, herdrPkg, ... }: {
  # Linux Home Manager counterpart of nix-darwin/herdr.nix. Unlike macOS (where
  # Herdr historically came from Homebrew), the personal TRAE-enabled Herdr is
  # a Nix package here: home.packages puts bin/herdr in the Home Manager
  # profile, which sits ahead of ~/.local/bin in login shells, so the official
  # per-user install at ~/.local/bin/herdr is shadowed without being deleted.
  # Skipped on the docker layer, which must not perform network/plugin work at
  # activation.

  # The five fzf popup launcher links live in the shared
  # modules/herdr-launchers.nix, imported from every host layer.
  home.packages = [ herdrPkg ];

  home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # The Rust plugin binaries live under ~/.local/bin, which a non-login
    # activation shell does not always have. ~/.cargo/bin is needed because the
    # pinned herdr-projects fork ships no release assets: `plugin install`
    # builds it with the per-user rustup toolchain (no cargo in the nix host
    # package set by design). The personal Herdr package is pinned explicitly
    # via HERDR_CLI and also prepended to PATH.
    export PATH="${herdrPkg}/bin:${config.home.profileDirectory}/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    HERDR_CLI="${herdrPkg}/bin/herdr" \
      HERDR_TEMPLATE=${../config/herdr/config.toml} \
      HERDR_AGENT_INTEGRATIONS="claude codex" \
      HERDR_SIDEBAR_INSTALLER=${../config/herdr/install-sidebar-policy.cjs} \
      HERDR_SIDEBAR_POLICY=${../config/herdr/sidebar-policy.cjs} \
      HERDR_PORTAL_POLICY=${../config/herdr/portal-policy.py} \
      HERDR_REPO_LIST_INSTALLER=${
        ../config/herdr/install-projects-repo-list.cjs
      } \
      HERDR_REPO_LIST_PATCH=${../patches/herdr-projects-multiline-repos.patch} \
      bash ${../install-herdr-plugins.sh}
  '';
}
