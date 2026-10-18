{ config, lib, pkgs, homeDir, username, ... }:
let omniwmEnabled = config.dotNix.windowManager == "omniwm";
in {
  options.dotNix.windowManager = lib.mkOption {
    type = lib.types.enum [ "aerospace" "omniwm" ];
    default = "aerospace";
    description =
      "Desktop window manager; OmniWM trials are launched manually.";
  };

  config = lib.mkMerge [
    {
      environment.etc."dot-nix/window-manager".text =
        config.dotNix.windowManager + "\n";
    }
    (lib.mkIf omniwmEnabled {
      assertions = [{
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message =
          "OmniWM requires an Apple Silicon Mac running macOS 26 or newer.";
      }];

      # false means displays DO have separate Spaces. Logging out is required
      # before macOS applies a change to this setting.
      system.defaults.CustomUserPreferences."com.apple.spaces".spans-displays =
        lib.mkForce false;

      # Run only when the user activates the system, never during evaluation.
      # No OmniWM LaunchAgent: first launch and login startup remain user choices.
      system.activationScripts.preActivation.text = lib.mkBefore ''
        echo >&2 "[omniwm-trial] releasing the AeroSpace stack..."
        launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
          /bin/bash "${../config/omniwm/stop-aerospace.sh}"
      '';

      system.activationScripts.postActivation.text = lib.mkAfter ''
        echo >&2 "[omniwm-trial] OmniWM installed; log out/in if Spaces changed, then open /Applications/OmniWM.app manually."
        echo >&2 "[omniwm-trial] settings are owned by OmniWM at ${homeDir}/.config/omniwm/settings.toml (or XDG_CONFIG_HOME); existing settings are not overwritten."
        echo >&2 "[omniwm-trial] seeding curated keybindings onto the OmniWM-owned settings (seed-once per revision)..."
        launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
          env OMNIWM_CONFIG_DIR=${homeDir}/.config/omniwm \
          /bin/bash "${../config/omniwm/apply-hotkey-overrides.sh}" || true
      '';
    })
  ];
}
