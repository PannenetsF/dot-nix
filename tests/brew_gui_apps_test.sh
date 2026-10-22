#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
homebrew_module="${repo_root}/nix-darwin/homebrew.nix"
darwin_config="${repo_root}/nix-darwin/configuration.nix"
gui_module="${repo_root}/nix-darwin/gui-apps.nix"
old_gui_module="${repo_root}/modules/mac-gui-app.nix"

assert_contains() {
  local file="$1"
  local text="$2"
  local message="$3"

  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local text="$2"
  local message="$3"

  if grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_contains "$darwin_config" "./homebrew.nix" "expected nix-darwin to import homebrew.nix"
assert_contains "$darwin_config" "./gui-apps.nix" "expected nix-darwin to import gui-apps.nix"
assert_contains "$homebrew_module" "enable = true;" "expected nix-darwin homebrew module to be enabled"
assert_not_contains "$homebrew_module" '"wezterm@nightly"' "did not expect the WezTerm nightly cask"
assert_not_contains "$homebrew_module" '"wezterm"' "did not expect the WezTerm stable cask"
assert_not_contains "$gui_module" "pkgsUnstable.wezterm" "did not expect WezTerm in Nix GUI packages"
assert_not_contains "$gui_module" "pkgsUnstable.alacritty" "did not expect Alacritty to remain in Nix GUI packages"
assert_not_contains "$homebrew_module" '"alacritty"' "did not expect the deprecated Alacritty Homebrew cask"
assert_contains "$homebrew_module" '"font-ubuntu-mono-nerd-font"' "expected the terminal-safe UbuntuMono Nerd Font cask"
assert_not_contains "$homebrew_module" '"font-ubuntu-nerd-font"' "did not expect the proportional Ubuntu Nerd Font cask"
assert_contains "$homebrew_module" "\"dot-nix/local\"" "expected local tap to provide patched casks"
assert_contains "$homebrew_module" "trust dot-nix/local" "expected local tap to be trusted before Homebrew bundle"
assert_contains "$homebrew_module" "branch -M main" "expected an existing local tap branch to be renamed without losing history"
assert_contains "$homebrew_module" "symbolic-ref HEAD refs/heads/main" "expected the generated local tap to use a deterministic main branch"
assert_contains "$homebrew_module" "pull --ff-only -q origin main" "expected the installed local tap checkout to refresh before cask migration"
# The retired AeroSpace cask/JankyBorders formula are archived under
# deprecated/ and must no longer be managed by Homebrew.
assert_not_contains "$homebrew_module" "aerospace-patched" "did not expect the retired patched AeroSpace cask to be staged"
assert_not_contains "$homebrew_module" "nikitabobko/tap/aerospace" "did not expect the upstream AeroSpace cask"
assert_not_contains "$homebrew_module" '"felixkratz/formulae"' "did not expect the retired JankyBorders tap"
assert_not_contains "$homebrew_module" "formulae/borders" "did not expect the retired JankyBorders formula"
assert_contains "$homebrew_module" "untap nikitabobko/tap" "expected the obsolete upstream AeroSpace tap to be removed"
assert_contains "$homebrew_module" "untap felixkratz/formulae" "expected the obsolete JankyBorders tap to be removed"
assert_contains "$homebrew_module" '"omniwm"' "expected the OmniWM cask in the declarative cask list"
# emacs-plus lives only in the d12frosted/emacs-plus tap; the tap must be
# declared and the formula fully-qualified, or `brew bundle` fails with
# "No available formula with the name emacs-plus".
assert_contains "$homebrew_module" '"d12frosted/emacs-plus"' "expected the emacs-plus tap to be declared"
assert_contains "$homebrew_module" '"d12frosted/emacs-plus/emacs-plus"' "expected emacs-plus to be installed from its tap, fully-qualified"
# Homebrew 4.4+ refuses formulae from new taps until explicitly trusted.
assert_contains "$homebrew_module" "tap d12frosted/emacs-plus" "expected the emacs-plus tap to be tapped before bundle"
assert_contains "$homebrew_module" "trust d12frosted/emacs-plus" "expected the emacs-plus tap to be trusted before bundle"
if grep -Eq '^[[:space:]]*"emacs-plus"[[:space:]]*$' "$homebrew_module"; then
  echo "did not expect a bare emacs-plus formula with no tap" >&2
  exit 1
fi
# emacs-plus is a formula and ships Emacs.app only in its prefix; the
# postActivation hook must symlink both bundles into /Applications from
# the stable opt path (a Cellar path breaks on every formula upgrade),
# re-register them with LaunchServices (Spotlight ignores symlinks), and
# never clobber a pre-existing real bundle.
assert_contains "$homebrew_module" 'opt/emacs-plus' "expected Emacs.app symlinked from the stable opt path, not the versioned Cellar"
assert_not_contains "$homebrew_module" "Cellar/emacs-plus" "did not expect a versioned Cellar path for the Emacs.app link"
assert_contains "$homebrew_module" '"Emacs.app"' "expected Emacs.app to be linked into /Applications"
assert_contains "$homebrew_module" '"Emacs Client.app"' "expected Emacs Client.app to be linked into /Applications"
assert_contains "$homebrew_module" "ln -sfn" "expected Emacs.app to be deployed as a self-healing symlink"
assert_contains "$homebrew_module" "lsregister" "expected LaunchServices re-registration so Spotlight indexes the symlinked apps"
assert_contains "$homebrew_module" "is not a symlink, leaving it alone" "expected a guard that preserves a pre-existing real Emacs.app"
assert_contains "$homebrew_module" "untap whatpulse/whatpulse" "expected stale upstream WhatPulse tap to be removed before Homebrew bundle"
assert_contains "$homebrew_module" "whatpulse-mac-arm-latest.dmg" "expected WhatPulse cask to use the working latest DMG URL"
assert_contains "$homebrew_module" "whatpulse-mac-latest.dmg" "expected the WhatPulse cask to provide the Intel latest DMG URL"
assert_contains "$homebrew_module" "uname -m" "expected the WhatPulse DMG URL to be selected from the machine's arch at activation time"
assert_contains "$homebrew_module" 'arm64)' "expected WhatPulse arch detection to handle Apple Silicon"
assert_contains "$homebrew_module" 'x86_64)' "expected WhatPulse arch detection to handle Intel"
assert_contains "$homebrew_module" 'Casks/whatpulse.rb" <<RUBY' "expected the WhatPulse heredoc to expand the arch-specific URL variable"
assert_contains "$homebrew_module" 'url "$whatpulse_url"' "expected the generated WhatPulse cask to use the arch-selected URL"
assert_contains "$homebrew_module" "chmodbpf.rb\" <<'RUBY'" "expected the universal ChmodBPF heredoc to stay quoted and byte-stable"
assert_not_contains "$homebrew_module" "\"whatpulse/whatpulse\"" "did not expect stale upstream WhatPulse tap"
assert_not_contains "$homebrew_module" "trust --tap whatpulse/whatpulse" "did not expect trust bootstrap for stale upstream WhatPulse tap"

if [[ -e "$old_gui_module" ]]; then
  echo "expected modules/mac-gui-app.nix to be removed after moving GUI app management to nix-darwin" >&2
  exit 1
fi

for cask in \
  1password \
  omniwm \
  chatgpt \
  cc-switch \
  claude \
  claude-code \
  codex \
  codex-app \
  firefox \
  karabiner-elements \
  kitty \
  maccy \
  microsoft-edge \
  raycast \
  snipaste \
  visual-studio-code \
  dot-nix/local/whatpulse-chmodbpf \
  dot-nix/local/whatpulse; do
  assert_contains "$homebrew_module" "\"$cask\"" "expected $cask to be installed as a Homebrew cask"
done

for unwanted in brave inkscape soduto updf demumble; do
  assert_not_contains "$homebrew_module" "$unwanted" "did not expect $unwanted in nix-darwin Homebrew config"
  assert_not_contains "$gui_module" "$unwanted" "did not expect $unwanted in Nix GUI packages"
done

for moved in _1password-gui karabiner-elements kitty maccy raycast vscode; do
  assert_not_contains "$gui_module" "$moved" "expected $moved to move out of Nix GUI packages"
done

# The retired tiling-WM stack moved to deprecated/00-aerospace-indicator/;
# the GUI module only keeps fonts and must define none of its launchd glue.
assert_not_contains "$gui_module" "launchd.user.agents.aerospace" "did not expect a retired AeroSpace launchd agent"
assert_not_contains "$gui_module" "launchd.user.agents.borders" "did not expect a retired borders launchd agent"
assert_not_contains "$gui_module" "bordersCli" "did not expect retired JankyBorders glue in the GUI module"
assert_not_contains "$gui_module" "renderAerospaceConfig" "did not expect the retired AeroSpace renderer in the GUI module"
assert_contains "$gui_module" "nerd-fonts.shure-tech-mono" "expected desktop fonts to move into nix-darwin GUI module"
assert_contains "$gui_module" "sketchybar-app-font" "expected sketchybar app font to move into nix-darwin GUI module"
