# nix-darwin

This directory contains macOS system-level configuration managed by nix-darwin.

`init.sh` uses this path by default on macOS. Keep user-level files, shell
settings, CLI packages, and app configs in `home.nix` and `modules/`. Move
settings here only when they need nix-darwin system capabilities, such as macOS
defaults, Homebrew declarations, LaunchDaemons, or machine-level services.

Linux server setup must stay outside this directory and continue to flow
through `modules/linux.nix` and `install-linux-server.sh`.
