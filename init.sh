#! /usr/bin/bash
set -ex

apt update
apt install nscd git -y 

git config --global core.sshCommand 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

mkdir -m 0755 -p /nix && groupadd -r nixbld && chown root /nix \
      && for n in $(seq 1 10); do useradd -c "Nix build user $n" -d /var/empty -g nixbld -G nixbld -M -N -r -s "$(command -v nologin)" "nixbld$n"; done

[[ -n "$PF_http_proxy" ]] && export http_proxy=$PF_http_proxy
[[ -n "$PF_https_proxy" ]] && export https_proxy=$PF_https_proxy
[[ -n "$PF_no_proxy" ]] && export no_proxy=$PF_no_proxy

sh <(curl --proto '=https' --tlsv1.2 -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --no-daemon --no-channel-add
USER=root . $HOME/.nix-profile/etc/profile.d/nix.sh
echo "USER=root . \$HOME/.nix-profile/etc/profile.d/nix.sh" >> ~/.bashrc
source ~/.bashrc

[[ -n "$PF_http_proxy" ]] && export http_proxy=$PF_http_proxy
[[ -n "$PF_https_proxy" ]] && export https_proxy=$PF_https_proxy
[[ -n "$PF_no_proxy" ]] && export no_proxy=$PF_no_proxy

nix-channel --add https://mirrors.tuna.tsinghua.edu.cn/nix-channels/nixpkgs-unstable nixpkgs
nix-channel --update

mkdir -p ~/.config/nix/

git clone https://github.com/PannenetsF/dot-nix.git ~/.config/nix-hm
echo "substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org/" > ~/.config/nix/nix.conf

USER=root nix --extra-experimental-features "nix-command flakes" \
  run nixpkgs#home-manager -- \
  --extra-experimental-features "nix-command flakes" \
  switch --flake $HOME/.config/nix-hm/#root

echo "USER=root . \$HOME/.nix-profile/etc/profile.d/nix.sh" >> ~/.zshrc
