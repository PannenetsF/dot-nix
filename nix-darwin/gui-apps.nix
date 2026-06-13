{ lib, pkgs, homeDir, username, ... }: {
  environment.systemPackages = with pkgs; [
    aerospace
    nerd-fonts.shure-tech-mono
    sketchybar-app-font
  ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "aerospace config..."
    install -d -o ${username} -g staff "${homeDir}/.config/aerospace"
    ln -sfn "${../config/aerospace/aerospace.toml}" "${homeDir}/.config/aerospace/aerospace.toml"
    rm -f "${homeDir}/.aerospace.toml"
    chown -h ${username}:staff "${homeDir}/.config/aerospace/aerospace.toml" 2>/dev/null || true

    install -d -o ${username} -g staff "${homeDir}/Library/Logs/aerospace"
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.aerospace" 2>/dev/null || true
  '';

  launchd.user.agents.aerospace.serviceConfig = {
    Label = "org.nix-community.home.aerospace";
    Program =
      "${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
    KeepAlive = true;
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/aerospace/aerospace.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/aerospace/aerospace.err.log";
  };
}
