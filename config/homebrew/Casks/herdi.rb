# Herdi: the herdr-remote menu-bar client (https://github.com/dcolinmorgan/herdr-remote).
# Upstream publishes only a GitHub DMG (no Homebrew cask), so it rides the
# repo's dot-nix/local tap like aerospace-patched. The app bundle is ad-hoc
# signed and NOT notarized (`spctl --assess` rejects it): on first launch the
# user must right-click -> Open (or System Settings -> Privacy & Security ->
# Open Anyway). The .app is deliberately not added to
# brew/unquarantine-casks.sh — TCC App Management makes xattr removal on app
# bundles EPERM, and unquarantine is reserved for bare CLI binaries there.
cask "herdi" do
  version "0.8.1"
  sha256 "21b16af040961158dfdc5bf73d31486e261637aca762fa5f5ed5581d0e2df9d5"

  url "https://github.com/dcolinmorgan/herdr-remote/releases/download/v#{version}/Herdi-#{version}.dmg"
  name "Herdi"
  desc "Menu-bar monitor and remote control for herdr agents"
  homepage "https://github.com/dcolinmorgan/herdr-remote"

  app "Herdi.app"
end
