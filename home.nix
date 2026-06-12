{ config, pkgs, pkgsUnstable, lib, system, isHost ? false, ... }: {
  # NOTE: Home Manager expects `home.homeDirectory` to be an absolute path.
  # We prefer $HOME (works for both macOS/Linux), and fall back to a reasonable
  # default based on `system` + $USER when $HOME is unavailable (e.g. pure eval).
  # If neither is available, fail with a clear error.
  _module.args = let
    debug = builtins.getEnv "NIX_HM_DEBUG" == "1";
    userEnv = builtins.getEnv "NIX_HM_USER";
    homeOverride = builtins.getEnv "NIX_HM_HOME";
    user = if userEnv != "" then userEnv else builtins.getEnv "USER";
    homeEnv =
      if homeOverride != "" then homeOverride else builtins.getEnv "HOME";
    isDarwin = builtins.match ".*-darwin" system != null;
    inferredHome = if user == "" then
      ""
    else if isDarwin then
      "/Users/${user}"
    else if user == "root" then
      "/root"
    else
      "/home/${user}";
    homeDirRaw = if homeEnv != "" then homeEnv else inferredHome;
    homeDir = if debug then
      builtins.trace
      "[home.nix][debug] system=${system} USER='${user}' HOME='${homeEnv}' NIX_HM_HOME='${homeOverride}' inferredHome='${inferredHome}' homeDir='${homeDirRaw}'"
      homeDirRaw
    else
      homeDirRaw;
  in {
    _user = user;
    _homeDir = if homeDir != "" && builtins.substring 0 1 homeDir == "/" then
      homeDir
    else
      throw
      "home.homeDirectory is empty or not absolute; please set HOME/USER env or hardcode home.homeDirectory";
  };

  imports = [ ./modules/common.nix ]
    ++ lib.optionals isHost [ ./modules/host.nix ]
    ++ lib.optionals (isHost && builtins.match ".*-darwin" system != null)
    [ ./modules/mac-gui-app.nix ]
    ++ (if builtins.match ".*-linux" system != null then
      [ ./modules/linux.nix ]
    else
      [ ]) ++ (if builtins.match ".*-darwin" system != null then
        [ ./modules/darwin.nix ]
      else
        [ ]);

  home = {
    username = config._module.args._user;
    homeDirectory = config._module.args._homeDir;
    stateVersion = "25.05";
  };
}
