{ config, lib, homeDir, username, ... }:
let
  # Shared, platform-independent body. The same script is run directly (no
  # privilege crossing) by modules/herdr.nix under Home Manager on Linux.
  herdrPluginScript = ../install-herdr-plugins.sh;
  herdrConfig = ../config/herdr/config.toml;
  herdrCli = "${config.homebrew.brewPrefix}/herdr";
  # sudo's env_reset hands the executed command a bare secure_path with none
  # of the Home Manager / nix-darwin profile directories, so the bare `node`
  # herdr spawns for Node plugin build hooks and actions fails to start (the
  # Rust plugins are self-contained binaries and never hit this). Re-prepend
  # the profile and Homebrew bin directories via env(1). ~/.cargo/bin is
  # needed because the pinned herdr-projects fork ships no release assets:
  # `plugin install` builds it with the user's per-user rustup toolchain.
  pluginPath = lib.concatStringsSep ":" [
    "/etc/profiles/per-user/${username}/bin"
    "${homeDir}/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "${config.homebrew.brewPrefix}"
    "${homeDir}/.cargo/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in {
  # nix-darwin postActivation runs as root. Cross into the target user exactly
  # once (launchctl asuser gives the user's GUI session context for sudo) and
  # run the whole shared script there, so files are created user-owned and no
  # per-command sudo/launchctl wrapper is needed. The script tolerates a
  # missing herdr binary (it still lands the template), so it always runs.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "herdr config..."
    launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
      env PATH="${pluginPath}" \
      CC=/usr/bin/cc \
      HERDR_TEMPLATE="${herdrConfig}" \
      HERDR_CLI="${herdrCli}" \
      HERDR_PUSH_RELAY_URL="http://127.0.0.1:8375" \
      bash "${herdrPluginScript}"
  '';
}
