#!/usr/bin/env bash
set -euo pipefail

# Regression coverage for the Doom Emacs bootstrap: the Doom CLI v2
# env-file syntax and the macOS font casks that kitty and Doom share.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
	local file="$1"
	local pattern="$2"
	local message="$3"
	if ! grep -Fq "$pattern" "${repo_root}/${file}"; then
		echo "$message" >&2
		exit 1
	fi
}

assert_not_contains() {
	local file="$1"
	local pattern="$2"
	local message="$3"
	if grep -Fq "$pattern" "${repo_root}/${file}"; then
		echo "$message" >&2
		exit 1
	fi
}

bash -n "${repo_root}/install-doom.sh"

assert_file_exists() {
	if [[ ! -f "${repo_root}/$1" ]]; then
		echo "expected $1 to be tracked" >&2
		exit 1
	fi
}

assert_file_exists "install-doom.sh"
assert_file_exists "install-common.sh"

# The shared library is sourced from the same directory so the Nix
# module reference must use the directory form.
assert_contains "install-doom.sh" '. "$script_dir/install-common.sh"' \
	"expected install-doom.sh to source the co-located install-common.sh"
assert_contains "nix-darwin/homebrew.nix" 'bash "${../.}/install-doom.sh"' \
	"expected nix-darwin to reference install-doom.sh in directory form"
assert_contains "modules/linux.nix" 'bash ${../.}/install-doom.sh' \
	"expected Linux HM activation to reference install-doom.sh in directory form"

# Doom CLI v2 removed `doom env -o FILE'; the output file is positional,
# and a `--` separator makes the parser drop it. The old invocation
# failed with "unknown option -o" and left no doomenv, aborting Emacs
# startup on `(doom-load-envvars-file ...)'.
assert_not_contains "install-doom.sh" 'doom" env -o' \
	"doom env -o was removed in Doom CLI v2; pass the output file positionally"
assert_contains "install-doom.sh" 'doom" env --allow-all "$DOOM_DIR/doomenv"' \
	"expected install-doom.sh to refresh the doomenv via positional output file"

# macOS GUI apps (kitty, Emacs) resolve fonts through CoreText; nix
# nerd-fonts packages stay invisible in the nix store, so the shared
# font families must be installed as casks.
assert_contains "nix-darwin/homebrew.nix" '"font-iosevka-nerd-font"' \
	"expected the Iosevka Nerd Font cask (kitty font_family and doom-font)"
assert_contains "nix-darwin/homebrew.nix" '"font-lxgw-wenkai"' \
	"expected the LXGW WenKai cask (Doom CJK fallback face)"
assert_contains "nix-darwin/homebrew.nix" '"font-symbols-only-nerd-font"' \
	"expected the Symbols Nerd Font cask (nerd-icons/doom-modeline hardcode that family)"
assert_contains "modules/host.nix" "nerd-fonts.symbols-only" \
	"expected Linux hosts to ship Symbols Nerd Font for doom-modeline"
