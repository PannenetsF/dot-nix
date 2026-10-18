# OmniWM

OmniWM is the managed window manager on Apple Silicon Macs (macOS 26+). It is
installed from the official Homebrew `omniwm` stable cask (not canaries); the
cask is not version-pinned and normal activation never upgrades installed
casks. `nix-darwin/window-manager.nix` asserts `aarch64-darwin` — Intel hosts
are no longer supported by the managed setup.

This document was written during the `feat/omniwm-trial` trial (now merged to
`main`); it is kept as the operational reference for the adopted setup. The
previous AeroSpace + workspace-indicator + JankyBorders stack is not deleted:
it is archived under `deprecated/00-aerospace-indicator/` with a manual
restore guide.

## What the configuration does

- Evaluation and tests never install software or change the running desktop;
  only the user runs activation (`bash ./init.sh`).
- Activation's preActivation runs `config/omniwm/stop-aerospace.sh`: it unloads
  the old managed AeroSpace/indicator/borders LaunchAgents and gracefully
  terminates remaining user-owned AeroSpace/borders instances. Their brew
  packages (cask cleanup is `none`) and `~/.config/aerospace/` stay on disk for
  rollback.
- OmniWM itself has no launch agent managed by Nix. First launch, TCC
  permissions and optional Start at Login are manual choices.
- The existing skhd shortcuts (Chrome and kitty quick-access terminal) remain.
  OmniWM's optional Quake terminal is not needed for the kitty shortcut.

## User-run activation and first launch

From the repository after reviewing the diff:

```bash
bash ./init.sh
```

Do not use `--upgrade` just to apply this setup. This applies the whole
configuration snapshot, not only the window-manager module.

1. Save work. Activation stops AeroSpace; do not run two window managers.
2. The config sets `com.apple.spaces spans-displays = false`, meaning
   **Displays have separate Spaces is enabled**. Log out and back in if the
   value changed; merely restarting OmniWM is not enough. (Accessibility and
   Input Monitoring grants likewise only take effect after a logout/login on
   some machines.)
3. Open `/Applications/OmniWM.app` manually. Grant Accessibility and Input
   Monitoring. Screen Recording is optional for Overview thumbnails; Full Disk
   Access is unnecessary for tiling.
4. Keep one native macOS Space per display initially; do not delete occupied
   Spaces without first moving their windows yourself.
5. Complete OmniWM's monitor setup. Its documented macOS display map is a
   technical staircase, with the physical desk layout entered separately in
   OmniWM. Monitor identities and routing stay local, not in tracked templates.

## Initial configuration

Let OmniWM generate its complete `settings.toml` on first launch. Its schema is
strict: a partial hand-written TOML file can invalidate the whole configuration.
We deliberately do not install a read-only Home Manager symlink, overwrite an
existing file, or copy settings from an unrelated release. GUI edits remain
writable at `${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml` (OmniWM
only honors an absolute XDG path).

Suggested baseline settings:

- **Layout:** Niri (the upstream default); use column width presets before
  changing many layout settings at once.
- **Focus Follows Mouse:** off initially, to avoid edge-sliver focus surprises.
- **Workspaces/Displays:** assign at least one workspace to each display using
  the setup assistant. Do not copy the old AeroSpace numeric monitor IDs.
- **Workspace Bar/Borders:** use OmniWM's built-ins; the old indicator and
  JankyBorders are disabled.
- **Gestures:** turn column scrolling off for the initial keyboard-only
  baseline, then configure a three/four-finger column scroll and disable
  conflicting macOS gestures.
- **Automation:** enable IPC in General only if you want `omniwmctl` queries.
- **Login startup:** leave off until the setup passes the checks below.

The curated niri-style keymap (see below) is seeded automatically; the binding
cheat sheet (Chinese, with skhd/herdr conflict notes) is
[omniwm-keybindings.md](omniwm-keybindings.md). Avoid the existing skhd
`Cmd+Shift+Return` and `Cmd+'`, and note the `Ctrl+Option+F` clash with
herdr's `C-A-f` documented in the cheat sheet.

### Curated keybindings (seeded, not owned by Nix)

`config/omniwm/apply-hotkey-overrides.sh` rewrites a fixed, machine-independent
keymap onto the OmniWM-owned settings.toml: `Option+hjkl` focus (move with
Shift), comma/period workspace scrolling in the niri style, `Option+R` size
cycle, layout toggle on `Option+Shift+/`, and `systemHyperTrigger = "None"`
(under `[general]`) so bare Option keys reach OmniWM instead of typing `¡` etc.
Monitor routing and workspace identities in the file are never touched.

- nix-darwin postActivation runs it as the target user. On the very first
  activation settings.toml does not exist yet (first launch is manual), so the
  script skips; after opening OmniWM once, rerun it manually
  (`bash config/omniwm/apply-hotkey-overrides.sh`) or activate again.
- It is seed-once per revision and writes
  `~/.config/omniwm/.hotkey-overrides.rev`; later GUI customizations survive
  activations. `OMNIWM_HOTKEY_FORCE=1` reapplies the current revision; a script
  revision bump rolls a new curated map out. Every run backs the file up
  (`settings.toml.bak-<ts>`, five newest kept) and restores the backup if the
  rewrite would create duplicate bindings or fail TOML validation.

## Validation after onboarding

```bash
bash tests/macos_acceptance.sh
# Optional, after enabling IPC:
omniwmctl --help
```

Manually exercise browser fullscreen/video, Cmd-Tab, browser relaunch, floating
dialogs, native terminal tabs, sleep/wake, dock/undock and lid close/reopen.
Check every display for stranded windows and incorrect focus. These checks
require a real desktop and are not established by Nix evaluation.

## Rollback to AeroSpace

There is no Nix option to switch back — the old WM glue is archived, not
wired. To restore the AeroSpace + indicator + borders stack, follow the
4-step manual procedure in
[`deprecated/00-aerospace-indicator/README.md`](../deprecated/00-aerospace-indicator/README.md).

Before any rollback: disable OmniWM's Start at Login if enabled, and quit
OmniWM normally from its menu so it can release parked windows — do not
force-kill it. The OmniWM app and its writable settings stay installed
(Homebrew cleanup is `none`); uninstall the cask only if you no longer want
it. Merely changing Git branches/worktrees never activates or rolls back the
running system.

## References

- <https://omniwm.app/guides/install/>
- <https://omniwm.app/help/known-limitations/>
- <https://omniwm.app/config/configuration/>
- <https://github.com/OmniNull/OmniWM#multi-monitor-setup>
