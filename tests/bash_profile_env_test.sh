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

bash_completion="$(nix_eval .#homeConfigurations.aarch64-darwin.config.programs.bash.enableCompletion)"
if [[ "$bash_completion" != "false" ]]; then
	echo "expected bash completion to stay disabled for macOS /bin/bash 3.2 compatibility" >&2
	exit 1
fi

shell_options="$(nix_eval --json .#homeConfigurations.aarch64-darwin.config.programs.bash.shellOptions)"
if [[ "$shell_options" == *"globstar"* || "$shell_options" == *"checkjobs"* ]]; then
	echo "expected bash shellOptions to avoid options unsupported by macOS /bin/bash 3.2" >&2
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
if [[ "$profile_extra" != *"/opt/homebrew/bin"* || "$profile_extra" != *"/opt/homebrew/sbin"* ]]; then
	echo "expected bash profile to include Apple Silicon Homebrew paths" >&2
	exit 1
fi
if [[ "$profile_extra" != *"/usr/local/bin"* || "$profile_extra" != *"/usr/local/sbin"* ]]; then
	echo "expected bash profile to include Intel Homebrew paths" >&2
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
