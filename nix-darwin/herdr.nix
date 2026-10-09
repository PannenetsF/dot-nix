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

      # herdr has no declarative plugin config, so install plugins here,
      # pinned to refs. `plugin install` re-installs even when current, so
      # guard on the installed ref.
      if ! herdr_as_user plugin list 2>/dev/null \
          | grep -q "furkankly.zoetrope.*@2d226f7"; then
        herdr_as_user plugin install -y \
          --ref 2d226f7eae7cf7b89fb7665300c419c21a6366b7 \
          furkankly/zoetrope/herdr-plugin
      fi

      # Version gates: plugin install talks to the running server and fails
      # hard against one too old to know the plugin's manifest features.
      # herdr-radar needs >= 0.9.0, herdr-projects >= 0.9.1.
      hp_bin="${homeDir}/.local/bin/herdr-projects"
      if herdr_as_user status --json 2>/dev/null | python3 -c '
import json, sys
v = json.load(sys.stdin)["server"]["version"]
sys.exit(0 if tuple(map(int, v.split("."))) >= (0, 9, 0) else 1)
' 2>/dev/null; then
        server_version="$(herdr_as_user status --json 2>/dev/null \
          | python3 -c 'import json,sys; print(json.load(sys.stdin)["server"]["version"])' 2>/dev/null)"

        # herdr-radar rewrites the sidebar Agents list with per-agent state
        # glyphs (working/blocked/done/idle tiers), project grouping and
        # activity ordering. It is a Node plugin: its interpreter comes from
        # host.nix (nodejs_22). Its install build hook and daemon manage three
        # marker-fenced blocks (tab-bar command, [ui.sidebar.*], [theme.custom])
        # plus the per-user icon font — none of which are in the repo template.
        # The template reinstall at the top of this activation WIPES those
        # blocks every run, so re-invoke configure afterwards to repair them.
        # Ordering caveat: Home Manager has already swapped kitty.conf to the
        # new generation by the time this runs, and config/kitty/kitty.conf
        # ships the plugin's exact font codepoint-map block — otherwise the
        # build hook hard-fails writing through the read-only Nix-store
        # symlink (its setup.js is not EACCES-safe).
        if ! herdr_as_user plugin list 2>/dev/null \
            | grep -q "hhdebb.herdr-radar.*@v1.4.2"; then
          herdr_as_user plugin install -y --ref v1.4.2 \
            hhdebb/herdr-radar
        fi
        herdr_as_user plugin action invoke configure \
          --plugin hhdebb.herdr-radar >/dev/null 2>&1 || true

        # herdr-projects requires server >= 0.9.1; plugin install talks to the
        # running server and fails hard against a stale one, so skip until the
        # server is restarted.
        if python3 -c 'import sys
sys.exit(0 if tuple(map(int, sys.argv[1].split("."))) >= (0, 9, 1) else 1)' "$server_version" 2>/dev/null; then
          if ! herdr_as_user plugin list 2>/dev/null \
              | grep -q "herdr-projects.*@v0.2.34"; then
            herdr_as_user plugin install -y --ref v0.2.34 \
              eliasstravik/herdr-projects
          fi
          # Sidebar grouping rows, the prefix+a popup and tab-bar entry are NOT
          # in the repo template: full configure adds them to the writable live
          # config after the template lands (and journals them so the plugin's
          # doctor validates them). It also maintains the agent progress hooks
          # and autoproject skill links. Idempotent, and repairs hooks lost to
          # other tools rewriting the agents' settings files.
          if [ -x "$hp_bin" ]; then
            launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
              "$hp_bin" configure >/dev/null 2>&1 || true
          fi
        else
          echo >&2 "herdr server is older than 0.9.1; restart herdr to install herdr-projects"
        fi
      else
        echo >&2 "herdr server is older than 0.9.0; restart herdr to install pinned plugins"
      fi

      herdr_as_user server reload-config 2>/dev/null || true
    fi
  '';
}
