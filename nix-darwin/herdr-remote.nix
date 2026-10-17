{ config, lib, pkgs, homeDir, username, ... }:
let
  # Python relay for herdr-remote (https://github.com/dcolinmorgan/herdr-remote):
  # accepts the herdr-push plugin's status events on 127.0.0.1:8375 and serves
  # the Herdi menu-bar app / phone / Telegram clients. Pinned with
  # fetchFromGitHub and run through `uv run --script` (PEP 723 inline deps);
  # the herdr-push plugin itself is installed by install-herdr-plugins.sh.
  relayVersion = "v0.8.1";
  relaySrc = "${
    pkgs.fetchFromGitHub {
      owner = "dcolinmorgan";
      repo = "herdr-remote";
      rev = relayVersion;
      sha256 = "0ysc9lpk74nm62vbzjllkm904za4pvh9b8y79c96pfhi08gflmhg";
    }
  }/relay";

  startHerdrRelay = pkgs.writeShellScript "start-herdr-relay" ''
    set -euo pipefail

    # Machine-local overrides, intentionally never tracked (portability rule:
    # no tokens/tunnel hosts in the repo). Optional keys used by the relay:
    # HERDR_RELAY_TOKEN (mandatory before binding beyond loopback),
    # HERDR_RELAY_HOST / HERDR_RELAY_PORT, HERDR_REMOTES.
    config_env="$HOME/.config/herdr-remote/config.env"
    [ -f "$config_env" ] && . "$config_env"

    # Defaults match herdr_relay.py itself: loopback 127.0.0.1:8375 needs no
    # auth token. install-herdr-plugins.sh seeds herdr-push's .env with
    # HERDR_RELAY=http://127.0.0.1:8375. Bind a non-loopback host only via the
    # local config.env above AND with HERDR_RELAY_TOKEN set (the relay refuses
    # to start otherwise).
    export HERDR_RELAY_HOST="''${HERDR_RELAY_HOST:-127.0.0.1}"
    export HERDR_RELAY_PORT="''${HERDR_RELAY_PORT:-8375}"

    # uv resolves the script's inline dependencies into the user uv cache on
    # first start (network needed once). The nixpkgs interpreter is passed
    # explicitly so uv does not download a CPython toolchain; Homebrew's bin
    # supplies the `herdr` CLI the relay polls for live pane state.
    export PATH="${pkgs.uv}/bin:${pkgs.python3}/bin:${config.homebrew.brewPrefix}:/usr/bin:/bin"
    exec uv run --python "${pkgs.python3}/bin/python3" \
      --script "${relaySrc}/herdr_relay.py"
  '';
in {
  system.activationScripts.herdrRemote.text = lib.mkAfter ''
    echo >&2 "herdr-remote relay..."
    install -d -o ${username} -g staff "${homeDir}/.config/herdr-remote"
    install -d -o ${username} -g staff "${homeDir}/Library/Logs/herdr-remote"
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.herdr-remote" 2>/dev/null || true
  '';

  launchd.user.agents.herdrRemote.serviceConfig = {
    Label = "org.nix-community.home.herdr-remote";
    Program = "${startHerdrRelay}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/herdr-remote/launchd.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/herdr-remote/launchd.err.log";
  };
}
