# Homebrew Bootstrap

This folder only bootstraps Homebrew itself and trusts the third-party taps used
by the nix-darwin Homebrew module.

Install or repair Homebrew with:

```bash
bash brew/install.sh
```

Homebrew packages, casks, and taps are declared in
`nix-darwin/homebrew.nix`. They are installed by nix-darwin during
`darwin-rebuild switch`.
