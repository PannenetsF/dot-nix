# OmniWM trial

This branch selects OmniWM on Apple Silicon and leaves Intel Macs on AeroSpace.
It uses the official Homebrew `omniwm` stable cask, not canaries. The cask is
not version-pinned; normal activation does not upgrade installed casks.
OmniWM requires Apple Silicon and macOS 26 or newer.

## Scope and isolation

- Work only in the separate `nix-hm-omniwm-trial` worktree on
  `feat/omniwm-trial`. It starts from committed `main`, not the other worktree's
  uncommitted edits. Review other ongoing environment changes before activating.
- Evaluation and tests do not install software or change the running desktop.
- Only the user runs activation. It stops the managed AeroSpace/indicator/borders
  agents and gracefully terminates remaining user-owned AeroSpace/borders
  instances. Their packages and source configuration are retained for rollback.
- OmniWM has no launch agent in this trial. First launch, TCC permissions and
  optional Start at Login are manual choices.
- The existing skhd shortcuts (Chrome and kitty quick-access terminal) remain.
  OmniWM's optional Quake terminal is not needed for the kitty shortcut.

## User-run activation and first launch

From this worktree, after reviewing the diff:

```bash
bash ./init.sh
```

Do not use the existing `hm-update` alias: it points at the original checkout.
Do not use `--upgrade` just to try this branch. `init.sh` uses its own worktree
because `flake.nix` is beside the script. Its current pull helpers skip linked
worktrees (`.git` is a file rather than a directory).
This applies the whole branch snapshot, not only the window-manager module.

1. Save work. Activation stops AeroSpace; do not run two window managers.
2. This branch sets `com.apple.spaces spans-displays = false`, meaning
   **Displays have separate Spaces is enabled**. Log out and back in if the
   value changed; merely restarting OmniWM is not enough.
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
writable at `${XDG_CONFIG_HOME:-$HOME/.config}/omniwm/settings.toml` (OmniWM only
honors an absolute XDG path).

Use these settings for the first trial:

- **Layout:** Niri (the upstream default); use column width presets before
  changing many layout settings at once.
- **Focus Follows Mouse:** off initially, to avoid edge-sliver focus surprises.
- **Workspaces/Displays:** assign at least one workspace to each display using
  the setup assistant. Do not copy AeroSpace's numeric monitor IDs.
- **Workspace Bar/Borders:** use OmniWM's built-ins; the old indicator and
  JankyBorders are disabled.
- **Gestures:** turn column scrolling off for the initial keyboard-only baseline,
  then configure a
  three/four-finger column scroll and disable conflicting macOS gestures.
- **Automation:** enable IPC in General only if you want `omniwmctl` queries.
- **Login startup:** leave off until the trial passes the checks below.

Shortcuts are upstream defaults, not an AeroSpace keymap migration. The default
binding cheat sheet (Chinese, with the AeroSpace migration and skhd/herdr
conflict notes) is [omniwm-keybindings.md](omniwm-keybindings.md). Change them
in Settings > Hotkeys after confirming the basic layout works. Avoid the
existing skhd `Cmd+Shift+Return` and `Cmd+'`, and note the default
`Ctrl+Option+F` clash with herdr's `C-A-f` documented in the cheat sheet.

### Curated keybindings (seeded, not owned by Nix)

`config/omniwm/apply-hotkey-overrides.sh` rewrites a fixed, machine-independent
keymap onto the OmniWM-owned settings.toml: `Option+hjkl` focus/move (arrows are
replaced), comma/period workspace scrolling in the niri style, `Option+R` size
cycle, layout toggle moved to `Option+Shift+/`, and `systemHyperTrigger =
"None"`. Monitor routing and workspace identities in the file are never touched.

- nix-darwin postActivation runs it as the target user. On the first trial
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

The Intel selection is structurally evaluated, but the repository's current
unstable nixpkgs input has dropped `x86_64-darwin` package support. Full Intel
system evaluation is a pre-existing limitation, not validated by this trial.

## Rollback

1. Disable OmniWM's Start at Login if you enabled it; quit OmniWM normally from
   its menu, so it can release parked windows. Do not force-kill it.
2. In this worktree's `nix-darwin/configuration.nix`, replace the
   `dotNix.windowManager` assignment with `dotNix.windowManager = "aerospace";`.
3. Run `bash ./init.sh` yourself. This restores the AeroSpace agents, rendering,
   indicator and JankyBorders, and the previous separate-Spaces preference.
4. Log out/in if the Spaces preference changed. Do not relaunch OmniWM alongside
   AeroSpace. Its app and writable settings remain installed because Homebrew
   cleanup is `none`; uninstall only if you no longer want to keep the trial.

Alternatively activate your original checkout after accounting for its unrelated
uncommitted changes. Merely changing Git branches/worktrees does not activate or
roll back the running system.

## References

- <https://omniwm.app/guides/install/>
- <https://omniwm.app/help/known-limitations/>
- <https://omniwm.app/config/configuration/>
- <https://github.com/OmniNull/OmniWM#multi-monitor-setup>
