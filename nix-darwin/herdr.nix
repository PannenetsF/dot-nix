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
      herdr_as_user() {
        launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
          "${herdrCli}" "$@"
      }

      # herdr has no declarative plugin config, so install the zoetrope plugin
      # here, pinned to a ref. `plugin install` re-installs even when current,
      # so guard on the installed ref.
      if ! herdr_as_user plugin list 2>/dev/null \
          | grep -q "furkankly.zoetrope.*@2d226f7"; then
        herdr_as_user plugin install -y \
          --ref 2d226f7eae7cf7b89fb7665300c419c21a6366b7 \
          furkankly/zoetrope/herdr-plugin
      fi

      herdr_as_user server reload-config 2>/dev/null || true
    fi
  '';
}
