{ config, lib, pkgs, homeDir, username, herdrPkg, ... }:
let
  # Python relay for herdr-remote (https://github.com/dcolinmorgan/herdr-remote):
  # accepts the herdr-push plugin's status events on 127.0.0.1:8375 and serves
  # the Herdi menu-bar app / phone / web clients. Pinned with
  # fetchFromGitHub and run through `uv run --script` (PEP 723 inline deps);
  # the herdr-push plugin itself is installed by install-herdr-plugins.sh.
  # The Telegram bot client is no longer run (see the note further down):
  # the fork still carries relay/herdr_telegram.py and the pf.8-pf.22 patches
  # to it, they are simply unstarted.
  # Upstream dcolinmorgan/herdr-remote v0.8.1 plus the nix-hm telegram patch
  # set (identity headers, transcript-based reads, markdown -> Telegram HTML,
  # human-audience filter, live dashboard, reusable pane cards, sticky focus
  # pane, persistent session bar, /switch selector whose two-line buttons put
  # the topic on line 1 and project > pane . session on line 2 (phone
  # display-cell budgets, transcript preview on session pick, pane-anchored
  # preview header); pf.14 mirrors the sidebar audience filter by forwarding
  # herdr-projects' hp_role/hp_project/hp_audience tokens (only coordinator/
  # session rows reach the bot; phantom cwd-basename projects are gone);
  # pf.15 namespaces the /project drill-down by (host, slug) so the same
  # project running on a remote stays its own @host row; pf.16 puts the
  # @host marker on every cross-machine surface (/agents, notification
  # headers, focus preview, session bar, dashboard groups/buttons);
  # pf.17 answers Claude Code single-select question menus (the
  # "N. Type something." row) with arbitrary text -- footer-verified so
  # numbered markdown lists in agent output are never driven -- and only
  # answers via respond while the pane is still blocked, so a stale prompt
  # id routes a fresh instruction through agent prompt; pf.18 makes every
  # explicit session open (picker tap / 🔄 recent / Read button) post a
  # FRESH preview at the chat bottom instead of silently editing the pane's
  # buried reusable message (which read as a dead/frozen button); only the
  # 🎯 current-pane bar key and /read keep in-place refresh; pf.19 lets a
  # direct loopback event push (`?d=`, no X-Forwarded-*/Via) through without
  # HERDR_RELAY_TOKEN -- herdr-push is plain curl and cannot send the token,
  # so with a token set every push 401'd; proxied requests (an ssh -R tunnel
  # also ends on loopback) still need it; pf.20 never exempts a WebSocket
  # upgrade (the token skips the origin check, so `/?d=` would otherwise
  # open a token-free session for any local page); pf.21 ships the
  # Projects-first web herd: coordinators and hand-started sessions grouped
  # by registered hp_project (+host); pf.22 makes Projects strictly
  # primary-only -- no hp_role=thread pane is ever its own card regardless of
  # hp_audience or status; human/stalled workers are coalesced into a
  # "N thread follow-ups" badge (one push, one chime, one timeline entry) on
  # the earliest live coordinator in the same (host, project), with All panes
  # keeping every live pane; a project with no live coordinator gets no card,
  # badge or alert; pf.23 replaces the global status sections with a
  # project-first accordion -- one compact row per (host, hp_project) that
  # expands inline into its coordinator/session panes, with the pf.22 strict
  # primary-only filter unchanged; expansion persists per browser and push
  # deep links expand the owning group;
  # maintained on the fork branch
  # pf/v0.8.1, tagged v0.8.1-pf.N -- same
  # scheme as the other herdr-* forks. To ship a new change: commit it on
  # pf/v0.8.1, tag v0.8.1-pf.<N+1>, bump relayPfTag and the hash below;
  # semantics are documented in AGENTS.md and asserted in
  # tests/darwin_herdr_config_test.sh.
  relayVersion = "v0.8.1";
  relayPfTag = "v0.8.1-pf.24";
  relaySource = pkgs.fetchFromGitHub {
    owner = "PannenetsF";
    repo = "herdr-remote";
    rev = relayPfTag;
    sha256 = "sha256-xiwpDlXQj/LjSwSQ0ED9WtTX+5y5zInpHHhJ1eGB4Ls=";
  };
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

    # Absolute pin to the personal Herdr binary. The relay prefers HERDR_BIN
    # over a PATH lookup, so this survives any later Homebrew/PATH drift and
    # matches the hand-managed Linux relay units, which set HERDR_BIN too.
    export HERDR_BIN="${herdrPkg}/bin/herdr"

    # uv resolves the script's inline dependencies into the user uv cache on
    # first start (network needed once). The nixpkgs interpreter is passed
    # explicitly so uv does not download a CPython toolchain; the personal
    # TRAE-enabled Herdr Nix package supplies the `herdr` CLI the relay polls
    # for live pane state (pinned before Homebrew so the core formula can
    # never be the polled binary).
    export PATH="${herdrPkg}/bin:${pkgs.uv}/bin:${pkgs.python3}/bin:${config.homebrew.brewPrefix}:/usr/bin:/bin"
    exec uv run --python "${pkgs.python3}/bin/python3" \
      --script "${relaySrc}/herdr_relay.py"
  '';

  # The Telegram bot client was removed on 2026-11-16. It was a WebSocket client
  # of the loopback relay, long-polling api.telegram.org. The company egress
  # refuses that domain (boe-fyq's proxy answers 504 for api.telegram.org while
  # letting google.com and github.com through), and Ovis' own one-way Telegram
  # alert webhook cannot carry the bot's /read, /reply, /switch or /interrupt, so
  # the whole notification-and-control line was dropped rather than split across
  # two transports. relay/herdr_telegram.py stays in the fork checkout; nothing
  # here starts it. To bring it back, restore this agent and re-add the
  # credentials to ~/.config/herdr-remote/secrets.env.
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
    # Unconditional restart: the relay has no dormant state. Its SIGINT/SIGTERM
    # handlers shut down gracefully with exit code 0, so a cleaner that treats a
    # successful exit as final parked the job forever after ANY SIGTERM -- a
    # `kickstart -k` from a mid-switch (even one that later fails before the
    # activation kickstart), bootout, or a manual kill -- and every client then
    # sat on "Relay disconnected" until the next successful darwin switch
    # (measured: 30h outage, 2026-10-30).
    KeepAlive = true;
    RunAtLoad = true;
    StandardOutPath = "${homeDir}/Library/Logs/herdr-remote/launchd.out.log";
    StandardErrorPath = "${homeDir}/Library/Logs/herdr-remote/launchd.err.log";
  };
}
