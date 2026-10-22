{ config, lib, ... }: {
  # Linux Home Manager counterpart of nix-darwin/herdr.nix. The herdr binary
  # itself is intentionally NOT a Nix package here (it keeps its official
  # per-user install, same as the Homebrew cask on macOS); this activation
  # only lands the config template and pins the plugin set. Skipped on the
  # docker layer, which must not perform network/plugin work at activation.

  # The four fzf popup launcher links live in the shared
  # modules/herdr-launchers.nix, imported from every host layer.

  home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # The official herdr install and the Rust plugin binaries live under
    # ~/.local/bin, which a non-login activation shell does not always have.
    # ~/.cargo/bin is needed because the pinned herdr-projects fork ships no
    # release assets: `plugin install` builds it with the per-user rustup
    # toolchain (no cargo in the nix host package set by design).
    export PATH="${config.home.profileDirectory}/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    HERDR_TEMPLATE=${../config/herdr/config.toml} \
      bash ${../install-herdr-plugins.sh}
  '';
}
