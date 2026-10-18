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
      intel = f.darwinConfigurations.x86_64-darwin;
      rollback = arm.extendModules {
        modules = [{ dotNix.windowManager = f.inputs.nixpkgs.lib.mkForce "aerospace"; }];
      };
      summarize = withActivation: system: let c = system.config; in {
        wm = c.dotNix.windowManager;
        agents = builtins.attrNames c.launchd.user.agents;
        casks = map (cask: cask.name) c.homebrew.casks;
        spansDisplays = c.system.defaults.CustomUserPreferences."com.apple.spaces".spans-displays;
        marker = c.environment.etc."dot-nix/window-manager".text;
      } // f.inputs.nixpkgs.lib.optionalAttrs withActivation {
        preActivation = c.system.activationScripts.preActivation.text;
        postActivation = c.system.activationScripts.postActivation.text;
      };
    # Intel policy can be checked without forcing unsupported unstable packages.
    in { arm = summarize true arm; intel = summarize false intel; rollback = summarize true rollback; }
  ')"

printf '%s\n' "$snapshot" | jq -e '
  .arm.wm == "omniwm" and
  (.arm.casks | index("omniwm") != null) and
  (.arm.casks | index("dot-nix/local/aerospace-patched") != null) and
  (.arm.agents | index("aerospace") == null) and
  (.arm.agents | index("aerospaceWorkspaceIndicator") == null) and
  (.arm.agents | index("borders") == null) and
  (.arm.agents | index("omniwm") == null) and
  .arm.spansDisplays == false and
  .arm.marker == "omniwm\n" and
  (.arm.preActivation | contains("stop-aerospace.sh")) and
  (.arm.postActivation | contains("aerospace config...") | not) and
  (.arm.postActivation | contains("existing settings are not overwritten")) and
  (.arm.postActivation | contains("apply-hotkey-overrides.sh")) and
  ([.intel, .rollback] | all(
    .wm == "aerospace" and
    (.casks | index("omniwm") == null) and
    (.agents | index("aerospace") != null) and
    (.agents | index("aerospaceWorkspaceIndicator") != null) and
    (.agents | index("borders") != null) and
    .spansDisplays == true
  )) and
  (.rollback.preActivation | contains("stop-aerospace.sh") | not) and
  (.rollback.postActivation | contains("aerospace config..."))
' >/dev/null
echo 'OmniWM trial ARM/Intel/rollback Nix evaluation checks passed'
