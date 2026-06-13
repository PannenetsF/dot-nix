{ pkgs, homeDir, username, ... }: {
  environment.systemPackages = with pkgs; [
    aerospace
    nerd-fonts.shure-tech-mono
    sketchybar-app-font
  ];

  system.activationScripts.aerospaceConfig.text = ''
    echo >&2 "aerospace config..."
    install -d -o ${username} -g staff "${homeDir}/.config/aerospace"
    ln -sfn "${../config/aerospace/aerospace.toml}" "${homeDir}/.config/aerospace/aerospace.toml"
    ln -sfn "${../config/aerospace/aerospace.toml}" "${homeDir}/.aerospace.toml"
    chown -h ${username}:staff "${homeDir}/.config/aerospace/aerospace.toml" "${homeDir}/.aerospace.toml" 2>/dev/null || true

    install -d -o ${username} -g staff "${homeDir}/Library/Logs/aerospace"
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
