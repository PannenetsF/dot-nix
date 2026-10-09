#!/usr/bin/env bash
# herdr-projects launcher: attach one or more local git repositories to an
# existing project. Bound to prefix+shift+a as a herdr type="popup" command:
# fzf picks the project, then fzf --multi picks repos (already-attached ones
# are filtered out). The popup's settings editor only takes a typed path.
#
# Roots: HP_PROJECT_ROOTS (colon-separated), default ~/Documents/workspace.
set -euo pipefail

# Popups close the moment this script exits, so a bare error would flash by.
die() {
  printf '\nERROR: %s\n' "$1" >&2
  printf 'press enter to close' >&2
  read -r _ || true
  exit 1
}

# herdr runs popups with a bare launchd PATH: fzf lives in the nix profile
# (/etc/profiles/per-user/<user>/bin) and git may come from homebrew, none of
# which a bare launchd PATH includes. Prepend the usual install folders before
# any dependency check so the popup works regardless of how it was launched.
for dir in \
  "$HOME/.local/bin" \
  "$HOME/.cargo/bin" \
  "$HOME/.nix-profile/bin" \
  "/etc/profiles/per-user/${USER:-$(id -un)}/bin" \
  "/opt/homebrew/bin" \
  "/usr/local/bin"
do
  [ -d "$dir" ] && PATH="$dir:$PATH"
done
export PATH

hp_bin="${HERDR_PROJECTS_BIN:-$HOME/.local/bin/herdr-projects}"
[ -x "$hp_bin" ] || hp_bin="$(command -v herdr-projects 2>/dev/null || true)"
[ -n "$hp_bin" ] || die "herdr-projects binary not found"
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"

# 1) pick the project (`list` lines: slug<TAB>status<TAB>summary)
project_line="$("$hp_bin" --root "$hp_root" list 2>/dev/null | fzf \
  --prompt='attach repo to project > ' \
  --header='Enter: choose project   Esc: cancel')" || exit 0
[ -n "$project_line" ] || exit 0
slug="${project_line%%$'\t'*}"
# `list` is ours, so a slug outside the slug charset means the output shape
# changed (or something else is on the other end); fail loudly instead of
# feeding garbage to `set`.
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "unexpected project list output: $project_line"
[ -d "$hp_root/$slug" ] || die "no such project: $slug"

# 2) repos already attached (path = "..." lines in the [[repos]] tables of the
# PROJECT.md TOML front matter). This list only hides already-attached repos
# from the picker, so a best-effort parse is fine; a missing PROJECT.md is not
# (the python3 tomllib version failed silently on every error).
project_md="$hp_root/$slug/PROJECT.md"
[ -r "$project_md" ] || die "PROJECT.md missing or unreadable: $project_md"
existing="$(awk '
  /^\+\+\+$/ { fence = !fence; next }
  fence && /^\[\[repos\]\]$/ { in_repos = 1; next }
  fence && /^\[/ { in_repos = 0 }
  fence && in_repos && /^path[[:space:]]*=/ {
    line = $0
    sub(/^[^"]*"/, "", line)
    sub(/".*$/, "", line)
    print line
  }
' "$project_md" | while IFS= read -r p; do
  # Expand a leading ~ so the filter below can compare real paths.
  case "$p" in
    "~/"*) printf '%s\n' "$HOME/${p#~/}" ;;
    "~") printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$p" ;;
  esac
done)"

# 3) pick new repos (multi), skipping attached ones (compare real paths once)
roots="${HP_PROJECT_ROOTS:-$HOME/Documents/workspace}"
list_repos() {
  old_ifs=$IFS
  IFS=:
  for root in $roots; do
    [ -d "$root" ] || continue
    # .git is a directory in a plain repo but a file in git worktrees and
    # submodules; match both so those show up in the picker too.
    find "$root" -maxdepth 4 \( -type d -o -type f \) -name .git -prune 2>/dev/null |
      while IFS= read -r gitdir; do
        printf '%s\n' "${gitdir%/.git}"
      done
  done
  IFS=$old_ifs
}

# Filter out already-attached repos before fzf. Kept as its own step (not in
# the fzf pipeline) so a python failure dies loudly instead of being masked by
# fzf's exit status. rstrip("\n") keeps leading/trailing spaces in paths.
candidates="$(list_repos | sort -u | HP_ATTACHED="$existing" python3 -c '
import os, sys
attached = {os.path.realpath(os.path.expanduser(p))
            for p in os.environ.get("HP_ATTACHED", "").splitlines() if p}
for line in sys.stdin:
    p = line.rstrip("\n")
    if p and os.path.realpath(os.path.expanduser(p)) not in attached:
        print(p)
')" || die "failed to filter already-attached repos"

selection="$(printf '%s\n' "$candidates" | fzf \
  --multi \
  --prompt="repos to attach to $slug > " \
  --header='Enter: attach selected (or highlighted) repo(s)   Tab: mark another   Esc: cancel')" || exit 0
[ -n "$selection" ] || die "no repo selected"

repos=()
while IFS= read -r line; do
  [ -n "$line" ] && repos+=("$line")
done <<< "$selection"

# 4) attach
for repo in "${repos[@]}"; do
  [ -d "$repo" ] || die "not a directory: $repo"
  # herdr-projects parses a repo path containing @ as PATH@MACHINE (a remote
  # machine), silently truncating the path; refuse it here.
  case "$repo" in
    *@*) die "repo path cannot contain @ (herdr-projects would parse it as PATH@MACHINE): $repo" ;;
  esac
  if msg="$("$hp_bin" --root "$hp_root" set "$slug" repos.add "$repo" 2>&1)"; then
    echo "attached $repo"
  elif printf '%s' "$msg" | grep -q 'already listed'; then
    # Idempotent: a repo already attached is not an error.
    echo "already attached: $repo"
  else
    printf '%s\n' "$msg" >&2
    die "'repos.add $repo' failed"
  fi
done
printf '\n%d repo(s) attached to %s\n' "${#repos[@]}" "$slug"
printf 'press enter to close'
read -r _ || true
