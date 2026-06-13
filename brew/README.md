# Homebrew Bootstrap

Homebrew packages, casks, and taps are declared in
`../nix-darwin/homebrew.nix` and applied by nix-darwin.

`install.sh` only bootstraps Homebrew itself and pre-trusts the taps needed by
that nix-darwin module.
