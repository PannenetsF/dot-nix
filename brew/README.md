# Homebrew Extras

This folder tracks macOS apps and utilities that are intentionally left in
Homebrew for now, usually because they are not available in the current Nix
package set or need Homebrew-specific taps.

Install or restore them with:

```bash
bash brew/install.sh
```

Check whether everything is already installed without treating outdated
packages as missing:

```bash
brew bundle check --no-upgrade --file=brew/Brewfile
```

If Homebrew refuses third-party taps because they are not trusted yet, trust the
formulae first:

```bash
brew trust --formula daipeihust/tap/im-select
brew trust --formula gromgit/fuse/sshfs-mac
```
