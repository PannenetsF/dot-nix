{ config, lib, homeDir, username, ... }:
let
  # herdr rewrites this file itself (settings UI, theme selection), so it is
  # installed as a writable regular file like the AeroSpace config, not as a
  # read-only Home Manager symlink into the Nix store.
  herdrConfig = ../config/herdr/config.toml;
  herdrCli = "${config.homebrew.brewPrefix}/herdr";
in {
  # nix-darwin runs a fixed allowlist of activation slots; reuse postActivation
  # like the AeroSpace config install in gui-apps.nix.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "herdr config..."
    install -d -o ${username} -g staff "${homeDir}/.config/herdr"
    # Drop any Home Manager-managed symlink from older generations first:
    # `install` would otherwise follow it into the read-only Nix store.
    rm -f "${homeDir}/.config/herdr/config.toml"
    install -m 0644 "${herdrConfig}" "${homeDir}/.config/herdr/config.toml"
    chown ${username}:staff "${homeDir}/.config/herdr/config.toml" 2>/dev/null || true

    if [ -x "${herdrCli}" ]; then
      launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
        "${herdrCli}" server reload-config 2>/dev/null || true
    fi
  '';
}
