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

# Plain `doom sync' only byte-compiles; without --aot the first run on a
# new machine leaves ~2000 packages on .elc with only lazy JIT
# native-compilation, causing per-feature stutters and background gcc
# churn for days. The first-time bootstrap must AOT-compile once.
assert_contains "install-doom.sh" 'doom" sync --aot' \
	"expected the first-time bootstrap to run 'doom sync --aot'"

# GUI Emacs.app launched via LaunchServices does not inherit the Home
# Manager profile; its ispell-compatible backend must come from Homebrew.
assert_contains "nix-darwin/homebrew.nix" '"aspell"' \
  "expected aspell for Doom flyspell in graphical Emacs"

# Homebrew's stable tdlib is frozen at the 2022 v1.8.0 tag; telega master
# tracks tdlib master and requires >= 1.8.66, so the formula must come
# from HEAD, and a pre-existing stable install must be migrated (brew
# bundle treats any installed tdlib as satisfied and never switches
# specs).
assert_contains "nix-darwin/homebrew.nix" 'name = "tdlib";' \
  "expected tdlib to be declared as an attrset"
assert_contains "nix-darwin/homebrew.nix" 'args = [ "HEAD" ];' \
  "expected tdlib installed from HEAD (stable is stuck at 1.8.0)"
assert_contains "nix-darwin/homebrew.nix" 'list --versions tdlib' \
  "expected a one-time migration that removes a stable tdlib install"
# telega's QR-code login dialog shells out to the qrencode binary; without
# it first launch falls back to the phone-number prompt in GUI Emacs.
assert_contains "nix-darwin/homebrew.nix" '"qrencode"' \
  "expected qrencode so telega can render QR-code login by default"

# macOS GUI apps (kitty, Emacs) resolve fonts through CoreText; nix
# nerd-fonts packages stay invisible in the nix store, so the shared
# font families must be installed as casks.
assert_contains "nix-darwin/homebrew.nix" '"font-sarasa-gothic"' \
	"expected the Sarasa Gothic cask (kitty font_family and doom-font use Sarasa Term SC)"
assert_contains "nix-darwin/homebrew.nix" '"font-lxgw-wenkai"' \
	"expected the LXGW WenKai cask (Doom's appended CJK fallback face)"
assert_contains "nix-darwin/homebrew.nix" '"font-symbols-only-nerd-font"' \
	"expected the Symbols Nerd Font cask (nerd-icons/doom-modeline hardcode that family)"
# Sarasa Term SC is the shared kitty/Doom face on Linux hosts too.
assert_contains "modules/host.nix" "sarasa-gothic" \
	"expected Linux hosts to ship Sarasa Gothic for kitty/Doom"
assert_contains "modules/host.nix" "nerd-fonts.symbols-only" \
	"expected Linux hosts to ship Symbols Nerd Font for doom-modeline"
