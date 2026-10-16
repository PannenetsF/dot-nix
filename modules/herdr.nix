{ config, lib, ... }: {
  # Linux Home Manager counterpart of nix-darwin/herdr.nix. The herdr binary
  # itself is intentionally NOT a Nix package here (it keeps its official
  # per-user install, same as the Homebrew cask on macOS); this activation
  # only lands the config template and pins the plugin set. Skipped on the
  # docker layer, which must not perform network/plugin work at activation.

  # fzf project launchers bound in config/herdr/config.toml (prefix+shift+c
  # new, prefix+ctrl+p pick, prefix+ctrl+n coordinator, prefix+shift+a add
  # repo). The template ships the key bindings on every platform, so without
  # these links the popup commands resolve to a missing ~/.local/bin binary on
  # Linux. Mirrors the home.file block in modules/darwin.nix; the scripts are
  # bash scripts runnable on both platforms (macOS ships bash 3.2), and the
  # macOS-only PATH entries are [ -d ]-guarded.
  home.file = {
    ".local/bin/herdr-new-project" = {
      source = ../config/herdr/new-project.sh;
      executable = true;
      force = true;
    };

    ".local/bin/herdr-pick-project" = {
      source = ../config/herdr/pick-project.sh;
      executable = true;
      force = true;
    };

    ".local/bin/herdr-add-repo" = {
      source = ../config/herdr/add-repo.sh;
      executable = true;
      force = true;
    };

    ".local/bin/herdr-new-coordinator" = {
      source = ../config/herdr/new-coordinator.sh;
      executable = true;
      force = true;
    };
  };

  home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # The official herdr install and the Rust plugin binaries live under
    # ~/.local/bin, which a non-login activation shell does not always have.
    export PATH="${config.home.profileDirectory}/bin:$HOME/.local/bin:$PATH"
    HERDR_TEMPLATE=${../config/herdr/config.toml} \
      bash ${../install-herdr-plugins.sh}
  '';
}
