{ config, pkgs, pkgsUnstable, lib, system, username, homeDir, isHost ? false
, isDocker ? false, ... }: {
  # NOTE: Home Manager expects `home.homeDirectory` to be an absolute path.
  # flake.nix derives these values once from NIX_HM_* / USER / HOME and passes
  # them here explicitly. Keep this module free of direct environment reads.
  _module.args = let
    debug = builtins.getEnv "NIX_HM_DEBUG" == "1";
    tracedHomeDir = if debug then
      builtins.trace
      "[home.nix][debug] system=${system} username='${username}' homeDir='${homeDir}'"
      homeDir
    else
      homeDir;
  in {
    _user = if username != "" then
      username
    else
      throw
      "home.username is empty; please set USER or NIX_HM_USER before evaluating";
    _homeDir =
      if tracedHomeDir != "" && builtins.substring 0 1 tracedHomeDir == "/" then
        tracedHomeDir
      else
        throw
        "home.homeDirectory is empty or not absolute; please set HOME or NIX_HM_HOME before evaluating";
  };

  # Layering:
  #   modules/common.nix    -- shared shell/CLI base, always imported.
  #   modules/host.nix       -- heavy dev toolchain, opt-in via isHost. A Docker
  #                             container stays lean, so isDocker forces it off.
  #   modules/linux.nix      -- Linux desktop / server layer (runs the network-
  #                             dependent install-linux-server.sh).
  #   modules/linux-docker.nix -- Linux container layer (no network activation).
  #   modules/darwin.nix     -- macOS user layer.
  imports = [ ./modules/common.nix ]
    ++ lib.optionals (isHost && !isDocker) [ ./modules/host.nix ]
    ++ (if builtins.match ".*-linux" system != null then
      (if isDocker then
        [ ./modules/linux-docker.nix ]
      else
        [ ./modules/linux.nix ])
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
