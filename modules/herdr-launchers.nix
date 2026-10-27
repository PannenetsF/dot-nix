{ ... }: {
  # fzf project launchers bound in config/herdr/config.toml (prefix+shift+c
  # new, prefix+ctrl+p pick, prefix+ctrl+n coordinator, prefix+ctrl+f focus
  # coordinator, prefix+shift+a add repo). The template ships the key
  # bindings on every platform, so without these links the popup commands
  # resolve to a missing ~/.local/bin binary.
  # Imported on every host layer (macOS via home.nix's isHost import, Linux
  # host likewise), keeping a single source of truth: any new launcher must
  # be added here once, not mirrored in modules/darwin.nix and
  # modules/herdr.nix separately. The scripts are bash runnable on both
  # platforms (macOS ships bash 3.2); the macOS-only PATH entries are
  # [ -d ]-guarded.
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

    ".local/bin/herdr-focus-coordinator" = {
      source = ../config/herdr/focus-coordinator.sh;
      executable = true;
      force = true;
    };

    ".local/bin/herdr-pick-session" = {
      source = ../config/herdr/pick-session.sh;
      executable = true;
      force = true;
    };

    # Shared preamble sourced by the launchers above; linked into the same
    # .local/bin directory because each launcher resolves one symlink hop and
    # sources the sibling next to its resolved nix-store file.
    ".local/bin/herdr-popup-lib.sh" = {
      source = ../config/herdr/herdr-popup-lib.sh;
      executable = true;
      force = true;
    };
  };
}
