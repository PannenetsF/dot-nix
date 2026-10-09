#!/usr/bin/env bash
# herdr-projects launcher: pick one or more local git repositories with fzf,
# then create (or open) the herdr-projects project attached to them. Bound to
# prefix+shift+c as a herdr type="popup" command, so it has an interactive TTY.
#
# Repository roots (colon-separated): HP_PROJECT_ROOTS, default
# ~/Documents/workspace. Repos up to 4 levels deep.
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
if [ -z "$hp_bin" ]; then
  echo "herdr-projects binary not found" >&2
  exit 1
fi
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"

roots="${HP_PROJECT_ROOTS:-$HOME/Documents/workspace}"

# Absolute repo paths, one per line (fuzzy match on the full path).
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

# --multi: Tab marks extra repos, Enter takes what is marked (or just the
# highlighted line for a single-repo project).
selection="$(list_repos | sort -u | fzf \
  --multi \
  --prompt='repos for new project > ' \
  --header='Enter: use selected (or highlighted) repo(s)   Tab: mark another   Esc: cancel')" || exit 0

[ -n "$selection" ] || exit 0
repos=()
while IFS= read -r line; do
  [ -n "$line" ] && repos+=("$line")
done <<< "$selection"
[ "${#repos[@]}" -gt 0 ] || die "no repo selected"
for repo in "${repos[@]}"; do
  [ -d "$repo" ] || die "selected path is not a directory: $repo"
  # herdr-projects parses a repo path containing @ as PATH@MACHINE (a remote
  # machine), silently truncating the path; refuse it here.
  case "$repo" in
    *@*) die "repo path cannot contain @ (herdr-projects would parse it as PATH@MACHINE): $repo" ;;
  esac
done
first_repo="${repos[0]}"
default_name="$(basename "$first_repo")"

# The project name is free text ("Erdos", "my project"); `herdr-projects new`
# derives the slug itself (lower-case, runs of other chars become one hyphen,
# at most 40 chars) and keeps the typed spelling as the display name.
printf 'Project name (displayed as typed; default: %s): ' "$default_name"
read -r name || exit 0
name="${name:-$default_name}"

hp_root="${HERDR_PROJECTS_ROOT:-$HOME/.herdr-projects}"
repo_args=()
for repo in "${repos[@]}"; do
  repo_args+=(--repo "$repo")
done

# `new` owns slug derivation: read the slug back from its "created `<slug>` …"
# output, or from its "`<slug>` already exists …" error when the folder is
# there already. Anything else is a real failure. `--` right before the name
# keeps a name starting with "-" from being parsed as an option (the --repo
# options must come before it, or clap treats them as positionals).
created="$("$hp_bin" --root "$hp_root" new "${repo_args[@]}" -- "$name" 2>&1)" && created_ok=1 || created_ok=0
if [ "$created_ok" = 1 ]; then
  # Restrict the slug capture to slug characters: a repo path containing a
  # backtick followed by " at " would otherwise satisfy a greedy `.*`.
  slug="$(printf '%s' "$created" | sed -n 's/^created `\([a-z0-9-]*\)` at .*$/\1/p')"
  [ -n "$slug" ] || die "project was created from '$name', but its slug could not be parsed; open it with prefix+ctrl+p"
elif slug="$(printf '%s' "$created" | sed -n 's/^.*`\([a-z0-9-]*\)` already exists .*$/\1/p')" && [ -n "$slug" ]; then
  echo "project '$slug' already exists; attaching any missing repos and opening it"
  for repo in "${repos[@]}"; do
    # Idempotent: a repo already attached is not an error, anything else is.
    msg="$("$hp_bin" --root "$hp_root" set "$slug" repos.add "$repo" 2>&1)" || {
      printf '%s' "$msg" | grep -q 'already listed' || {
        printf '%s\n' "$msg" >&2
        die "'set repos.add $repo' failed"
      }
    }
  done
else
  printf '%s\n' "$created" >&2
  die "'new' failed for '$name'"
fi

# Open the project in its own workspace tab: from a popup pane plain `open`
# would start the coordinator in the transient pane, which closes the moment
# this script exits. Outside Herdr --tab behaves like plain open.
#
# After a herdr restart the recorded socket is stale and `open` fails with a
# human-readable "... socket no longer exists ... pass --rebind ..." error.
# The plugin has no stable error code, so we match that text and retry once
# with --rebind; anything else is a real failure.
open_project() {
  local open_slug="$1" open_msg
  if open_msg="$("$hp_bin" --root "$hp_root" open "$open_slug" --tab 2>&1)"; then
    [ -n "$open_msg" ] && printf '%s\n' "$open_msg"
    return 0
  fi
  case "$open_msg" in
    *"no longer exists"*)
      printf '%s\n' "$open_msg" >&2
      echo "retrying with --rebind ..."
      if open_msg="$("$hp_bin" --root "$hp_root" open "$open_slug" --tab --rebind 2>&1)"; then
        [ -n "$open_msg" ] && printf '%s\n' "$open_msg"
        return 0
      fi
      ;;
  esac
  printf '%s\n' "$open_msg" >&2
  die "'open' failed for '$open_slug'"
}

open_project "$slug"
