{ lib, pkgs, homeDir, username, ... }:
let
  aerospaceConfigTemplate = ../config/aerospace/aerospace.toml;
  aerospaceIndicatorStart = ../config/aerospace/start_workspace_indicator.sh;
  aerospaceIndicatorSource = ../config/aerospace/workspace_indicator.swift;
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
    cli_path="/opt/homebrew/bin/aerospace"

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

    (
      for _ in $(seq 1 20); do
        sleep 0.5
        if [ -x "$cli_path" ] && "$cli_path" list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
          if "${renderAerospaceConfig}" "${aerospaceConfigTemplate}" "$config_file"; then
            "$cli_path" reload-config --no-gui >/dev/null 2>&1 || true
            /bin/sh -c 'printf . > /tmp/aerospace-workspace-indicator-dirty' >/dev/null 2>&1 || true
          fi
          break
        fi
      done
    ) &

    exec "$app_path/Contents/MacOS/AeroSpace"
  '';
  startAerospaceWorkspaceIndicator = pkgs.writeShellScript "start-aerospace-workspace-indicator" ''
    exec "${homeDir}/.config/aerospace/start_workspace_indicator.sh"
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
    install -m 0755 "${aerospaceIndicatorStart}" "${homeDir}/.config/aerospace/start_workspace_indicator.sh"
    install -m 0644 "${aerospaceIndicatorSource}" "${homeDir}/.config/aerospace/workspace_indicator.swift"
    chown ${username}:staff \
      "${homeDir}/.config/aerospace/start_workspace_indicator.sh" \
      "${homeDir}/.config/aerospace/workspace_indicator.swift" 2>/dev/null || true
    install -d -o ${username} -g staff "${homeDir}/Library/Caches/dot-nix"
    if [ -x /usr/bin/swiftc ]; then
      launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
        /usr/bin/swiftc "${homeDir}/.config/aerospace/workspace_indicator.swift" \
        -o "${homeDir}/Library/Caches/dot-nix/aerospace-workspace-indicator" 2>/dev/null || true
    fi
    rm -f \
      "${homeDir}/.config/aerospace/show_workspace_hud.sh" \
      "${homeDir}/.config/aerospace/show_workspace_hud.swift" \
      "${homeDir}/.config/aerospace/update_workspace_indicator.sh" \
      "${homeDir}/Library/Caches/dot-nix/aerospace-workspace-hud"
    rm -f "${homeDir}/.aerospace.toml"
    chown ${username}:staff "${homeDir}/.config/aerospace/aerospace.toml" 2>/dev/null || true

    install -d -o ${username} -g staff "${homeDir}/Library/Logs/aerospace"
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.aerospace" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.aerospace-workspace-indicator" 2>/dev/null || true
  '';

  launchd.user.agents.aerospace.serviceConfig = {
    Label = "org.nix-community.home.aerospace";
    Program = "${startAerospace}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/aerospace/aerospace.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/aerospace/aerospace.err.log";
  };

  launchd.user.agents.aerospaceWorkspaceIndicator.serviceConfig = {
    Label = "org.nix-community.home.aerospace-workspace-indicator";
    Program = "${startAerospaceWorkspaceIndicator}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/aerospace/workspace-indicator.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/aerospace/workspace-indicator.err.log";
  };
}
