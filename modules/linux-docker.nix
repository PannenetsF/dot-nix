{ config, pkgs, lib, ... }: {
  # Linux container / Docker layer.
  #
  # A container image is headless and usually ephemeral, so it must stay purely
  # declarative: unlike modules/linux.nix (the desktop / server layer) this one
  # deliberately does NOT run install-linux-server.sh. That script clones the
  # Neovim config and runs `nvim --headless -c 'Lazy'` / `TSUpdateSync`, which
  # need network access and an interactive-style home directory -- both of which
  # are the wrong assumptions inside an image build. The container gets the
  # shared shell/CLI config from modules/common.nix and nothing that reaches out
  # to the network at activation time.
  #
  # The Docker profile also intentionally excludes the heavy modules/host.nix
  # toolchain (see home.nix: isDocker forces the host layer off).
  home.emptyActivationPath = false;
}
