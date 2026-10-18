#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# A path flake includes new, uncommitted files without staging their contents.
snapshot="$(NIX_HM_USER=omniwm-test NIX_HM_HOME=/Users/omniwm-test \
  nix --extra-experimental-features 'nix-command flakes' eval --impure --json --expr '
    let
      f = builtins.getFlake ("path:" + toString ./.);
      arm = f.darwinConfigurations.aarch64-darwin;
      summarize = system: let c = system.config; in {
        agents = builtins.attrNames c.launchd.user.agents;
        casks = map (cask: cask.name) c.homebrew.casks;
        taps = map (tap: if builtins.isAttrs tap then tap.name else tap) c.homebrew.taps;
        brews = map (brew: if builtins.isAttrs brew then brew.name else brew) c.homebrew.brews;
        spansDisplays = c.system.defaults.CustomUserPreferences."com.apple.spaces".spans-displays;
        marker = c.environment.etc."dot-nix/window-manager".text;
        preActivation = c.system.activationScripts.preActivation.text;
        postActivation = c.system.activationScripts.postActivation.text;
      };
    in { arm = summarize arm; }
  ')"

printf '%s\n' "$snapshot" | jq -e '
  (.arm.casks | index("omniwm") != null) and
  (.arm.casks | index("dot-nix/local/aerospace-patched") == null) and
  (.arm.taps | index("felixkratz/formulae") == null) and
  ([.arm.brews[] | endswith("/borders")] | any | not) and
  (.arm.agents | index("aerospace") == null) and
  (.arm.agents | index("aerospaceWorkspaceIndicator") == null) and
  (.arm.agents | index("borders") == null) and
  (.arm.agents | index("omniwm") == null) and
  .arm.spansDisplays == false and
  .arm.marker == "omniwm\n" and
  (.arm.preActivation | contains("stop-aerospace.sh")) and
  (.arm.postActivation | contains("aerospace config...") | not) and
  (.arm.postActivation | contains("existing settings are not overwritten")) and
  (.arm.postActivation | contains("apply-hotkey-overrides.sh"))
' >/dev/null
echo 'OmniWM-only Nix evaluation checks passed'
