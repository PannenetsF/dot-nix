{ config, pkgs, pkgsUnstable, lib, system, ... }:
{
  # NOTE: Home Manager expects `home.homeDirectory` to be an absolute path.
  # We prefer $HOME (works for both macOS/Linux), and fall back to a reasonable
  # default based on `system` + $USER when $HOME is unavailable (e.g. pure eval).
  # If neither is available, fail with a clear error.
  _module.args =
    let
      debug = builtins.getEnv "NIX_HM_DEBUG" == "1";
      user = builtins.getEnv "USER";
      homeEnv = builtins.getEnv "HOME";
      isDarwin = builtins.match ".*-darwin" system != null;
      inferredHome =
        if user == "" then
          ""
        else if isDarwin then
          "/Users/${user}"
        else if user == "root" then
          "/root"
        else
          "/home/${user}";
      homeDirRaw = if homeEnv != "" then homeEnv else inferredHome;
      homeDir =
        if debug then
          builtins.trace "[home.nix][debug] system=${system} USER='${user}' HOME='${homeEnv}' inferredHome='${inferredHome}' homeDir='${homeDirRaw}'" homeDirRaw
        else
          homeDirRaw;
    in
    {
      _homeDir =
        if homeDir != "" && builtins.substring 0 1 homeDir == "/" then
          homeDir
        else
          throw "home.homeDirectory is empty or not absolute; please set HOME/USER env or hardcode home.homeDirectory";
    };

  imports =
    [ ./modules/common.nix ]
    ++ (
      if builtins.match ".*-linux" system != null then
        [ ./modules/linux.nix ]
      else
        [ ]
    )
    ++ (
      if builtins.match ".*-darwin" system != null then
        [ ./modules/darwin.nix ]
      else
        [ ]
    );

  home = {
    username = builtins.getEnv "USER";
    homeDirectory = config._module.args._homeDir;
    stateVersion = "25.05";
  };
}
