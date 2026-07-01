{ lib, pkgs, homeDir, username, ... }:
let
  aerospaceConfigTemplate = ../config/aerospace/aerospace.toml;
  renderAerospaceConfig = pkgs.writeShellScript "render-aerospace-config" ''
    exec ${pkgs.python3}/bin/python3 ${
      ../config/aerospace/render-config.py
    } "$@"
  '';
  startAerospace = pkgs.writeShellScript "start-aerospace" ''
    set -eu

    config_dir="${homeDir}/.config/aerospace"
    config_file="$config_dir/aerospace.toml"
    app_path="/Applications/AeroSpace.app"

    install -d "$config_dir"
    if ! "${renderAerospaceConfig}" "${aerospaceConfigTemplate}" "$config_file"; then
      cp "${aerospaceConfigTemplate}" "$config_file"
    fi

    if [ ! -x "$app_path/Contents/MacOS/AeroSpace" ]; then
      echo >&2 "AeroSpace.app is missing. Install it with Homebrew cask nikitabobko/tap/aerospace."
      exit 1
    fi

    for pid in $(pgrep -x AeroSpace 2>/dev/null || true); do
      kill "$pid" 2>/dev/null || true
    done

    exec "$app_path/Contents/MacOS/AeroSpace"
  '';
in {
  environment.systemPackages = with pkgs; [
    nerd-fonts.shure-tech-mono
    sketchybar-app-font
  ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "aerospace config..."
    install -d -o ${username} -g staff "${homeDir}/.config/aerospace"
    if ! "${renderAerospaceConfig}" "${aerospaceConfigTemplate}" "${homeDir}/.config/aerospace/aerospace.toml"; then
      cp "${aerospaceConfigTemplate}" "${homeDir}/.config/aerospace/aerospace.toml"
    fi
    rm -f "${homeDir}/.aerospace.toml"
    chown ${username}:staff "${homeDir}/.config/aerospace/aerospace.toml" 2>/dev/null || true

    install -d -o ${username} -g staff "${homeDir}/Library/Logs/aerospace"
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.aerospace" 2>/dev/null || true
  '';

  launchd.user.agents.aerospace.serviceConfig = {
    Label = "org.nix-community.home.aerospace";
    Program = "${startAerospace}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/aerospace/aerospace.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/aerospace/aerospace.err.log";
  };
}
