{ config, lib, pkgs, homeDir, username, ... }: {
  # OmniWM is the only managed window manager. The previous AeroSpace +
  # workspace indicator + JankyBorders stack is retired but archived under
  # deprecated/00-aerospace-indicator/, including a frozen snapshot of its
  # nix glue and manual restore instructions.
  assertions = [{
    assertion = pkgs.stdenv.hostPlatform.isAarch64;
    message = "OmniWM requires an Apple Silicon Mac running macOS 26 or newer.";
  }];

  environment.etc."dot-nix/window-manager".text = ''
    omniwm
  '';

  # false means displays DO have separate Spaces. Logging out is required
  # before macOS applies a change to this setting.
  system.defaults.CustomUserPreferences."com.apple.spaces".spans-displays =
    lib.mkForce false;

  # Run only when the user activates the system, never during evaluation.
  # No OmniWM LaunchAgent: first launch and login startup remain user choices.
  # The retired AeroSpace agents/processes are stopped so the two WMs never
  # run together, but their casks/formulae and configs are left on disk.
  system.activationScripts.preActivation.text = lib.mkBefore ''
    echo >&2 "[omniwm] releasing the retired AeroSpace stack..."
    launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
      /bin/bash "${../config/omniwm/stop-aerospace.sh}"
  '';

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "[omniwm] OmniWM installed; log out/in if Spaces changed, then open /Applications/OmniWM.app manually."
    echo >&2 "[omniwm] settings are owned by OmniWM at ${homeDir}/.config/omniwm/settings.toml (or XDG_CONFIG_HOME); existing settings are not overwritten."
    echo >&2 "[omniwm] seeding curated keybindings onto the OmniWM-owned settings (seed-once per revision)..."
    launchctl asuser "$(id -u ${username})" sudo --user=${username} --set-home \
      env OMNIWM_CONFIG_DIR=${homeDir}/.config/omniwm \
      /bin/bash "${../config/omniwm/apply-hotkey-overrides.sh}" || true
  '';
}
