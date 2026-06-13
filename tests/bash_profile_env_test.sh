#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nix_eval() {
	nix --extra-experimental-features 'nix-command flakes' eval --impure "$@"
}

cd "$repo_root"

bash_enabled="$(nix_eval .#homeConfigurations.aarch64-darwin.config.programs.bash.enable)"
if [[ "$bash_enabled" != "true" ]]; then
	echo "expected Home Manager to manage bash startup files" >&2
	exit 1
fi

profile_extra="$(nix_eval --raw .#homeConfigurations.aarch64-darwin.config.programs.bash.profileExtra)"
if [[ "$profile_extra" != *"/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"* ]]; then
	echo "expected bash profile to source the Nix daemon profile" >&2
	exit 1
fi
if [[ "$profile_extra" != *"hm-session-vars.sh"* ]]; then
	echo "expected bash profile to source Home Manager session variables" >&2
	exit 1
fi
if [[ "$profile_extra" != *"set +u"* || "$profile_extra" != *"set -u"* ]]; then
	echo "expected bash profile to source Home Manager session variables with nounset disabled" >&2
	exit 1
fi

bashrc_extra="$(nix_eval --raw .#homeConfigurations.aarch64-darwin.config.programs.bash.bashrcExtra)"
if [[ "$bashrc_extra" != *"hm-session-vars.sh"* ]]; then
	echo "expected bashrc to source Home Manager session variables" >&2
	exit 1
fi
if [[ "$bashrc_extra" != *"set +u"* || "$bashrc_extra" != *"set -u"* ]]; then
	echo "expected bashrc to source Home Manager session variables with nounset disabled" >&2
	exit 1
fi
