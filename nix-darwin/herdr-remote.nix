{ config, lib, pkgs, homeDir, username, ... }:
let
  # Python relay for herdr-remote (https://github.com/dcolinmorgan/herdr-remote):
  # accepts the herdr-push plugin's status events on 127.0.0.1:8375 and serves
  # the Herdi menu-bar app / phone / Telegram clients. Pinned with
  # fetchFromGitHub and run through `uv run --script` (PEP 723 inline deps);
  # the herdr-push plugin itself is installed by install-herdr-plugins.sh.
  relayVersion = "v0.8.1";
  relaySourceRaw = pkgs.fetchFromGitHub {
    owner = "dcolinmorgan";
    repo = "herdr-remote";
    rev = relayVersion;
    sha256 = "0ysc9lpk74nm62vbzjllkm904za4pvh9b8y79c96pfhi08gflmhg";
  };
  # Pinned upstream source + one local, out-of-tree patch. The patch makes the
  # Telegram bot render blocked/finished notifications as
  # "project > pane(title + pane id) > registered claude session", because the
  # stock header is just "<claude> blocked in <basename cwd>" and every
  # herdr-projects pane on one host reports agent=claude with the same/thread
  # cwd basename. A relayVersion bump that drifts the upstream file makes this
  # build fail loudly; tests/darwin_herdr_config_test.sh asserts the wiring.
  # Patch semantics documented in AGENTS.md.
  relaySource = pkgs.runCommandLocal "herdr-remote-${relayVersion}-source" {
    nativeBuildInputs = [ pkgs.patch ];
  } ''
    cp -r ${relaySourceRaw} $out
    chmod -R u+w $out
    patch -d "$out" -p1 < ${
      ../patches/herdr-remote-telegram-notifications.patch
    }
  '';
  relaySrc = "${relaySource}/relay";

  startHerdrRelay = pkgs.writeShellScript "start-herdr-relay" ''
    set -euo pipefail

    # Machine-local overrides, intentionally never tracked (portability rule:
    # no tokens/tunnel hosts in the repo). Optional keys used by the relay:
    # HERDR_RELAY_TOKEN (mandatory before binding beyond loopback),
    # HERDR_RELAY_HOST / HERDR_RELAY_PORT, HERDR_REMOTES.
    config_env="$HOME/.config/herdr-remote/config.env"
    # set -a so sourced vars (HERDR_RELAY_TOKEN, HERDR_REMOTES, HERDR_SESSION,
    # HTTPS_PROXY, ...) actually reach the uv/python child -- a plain `.` only
    # creates shell variables it never sees.
    set -a
    [ -f "$config_env" ] && . "$config_env"
    set +a

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

  # Telegram bot client for the relay (relay/herdr_telegram.py, v0.8.1). It is
  # a pure WebSocket *client* of the loopback relay: long-polling api.telegram.org
  # for commands and pushing blocked/done notifications, so the Mac needs only
  # outbound HTTPS -- no public IP, port forward, or Cloudflare tunnel. Credentials
  # live machine-locally in ~/.config/herdr-remote/secrets.env (0600, never in
  # the repo): HERDR_TG_TOKEN (BotFather) and HERDR_TG_CHAT_ID (the whitelisted
  # chat; bot ignores everyone else). config.env may additionally set HERDR_RELAY
  # (default ws://127.0.0.1:8375), HERDR_RELAY_TOKEN, or HTTPS_PROXY for networks
  # that cannot reach Telegram directly.
  startHerdrTelegram = pkgs.writeShellScript "start-herdr-telegram" ''
    set -euo pipefail

    config_dir="$HOME/.config/herdr-remote"
    # set -a: sourced assignments (HERDR_TG_TOKEN, HERDR_TG_CHAT_ID, optional
    # HTTPS_PROXY/HERDR_RELAY overrides) must be exported, or the uv/python
    # child starts with an empty token and exits immediately.
    set -a
    [ -f "$config_dir/config.env" ] && . "$config_dir/config.env"
    [ -f "$config_dir/secrets.env" ] && . "$config_dir/secrets.env"
    set +a

    # Dormant until the user opts in: exit 0 so KeepAlive (SuccessfulExit=false)
    # does not retry-loop on machines without a bot configured.
    if [ -z "''${HERDR_TG_TOKEN:-}" ]; then
      echo "herdr-telegram: HERDR_TG_TOKEN missing in $config_dir/secrets.env, staying dormant" >&2
      exit 0
    fi

    export HERDR_RELAY="''${HERDR_RELAY:-ws://127.0.0.1:8375}"
    if [ -n "''${HERDR_RELAY_TOKEN:-}" ] && [[ "$HERDR_RELAY" != *"token="* ]]; then
      export HERDR_RELAY="$HERDR_RELAY?token=$HERDR_RELAY_TOKEN"
    fi

    export PATH="${pkgs.uv}/bin:${pkgs.python3}/bin:/usr/bin:/bin"
    exec uv run --python "${pkgs.python3}/bin/python3" \
      --script "${relaySrc}/herdr_telegram.py"
  '';
in {
  system.activationScripts.herdrRemote.text = lib.mkAfter ''
    echo >&2 "herdr-remote relay..."
    install -d -o ${username} -g staff "${homeDir}/.config/herdr-remote"
    install -d -o ${username} -g staff "${homeDir}/Library/Logs/herdr-remote"
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.herdr-remote" 2>/dev/null || true
    launchctl kickstart -k "gui/$(id -u ${username})/org.nix-community.home.herdr-telegram" 2>/dev/null || true
  '';

  launchd.user.agents.herdrRemote.serviceConfig = {
    Label = "org.nix-community.home.herdr-remote";
    Program = "${startHerdrRelay}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/herdr-remote/launchd.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/herdr-remote/launchd.err.log";
  };

  launchd.user.agents.herdrTelegram.serviceConfig = {
    Label = "org.nix-community.home.herdr-telegram";
    Program = "${startHerdrTelegram}";
    KeepAlive = { SuccessfulExit = false; };
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/herdr-remote/telegram.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/herdr-remote/telegram.err.log";
  };
}
