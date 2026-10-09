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
[ -d "$hp_root/$slug" ] || die "no such project: $slug"

# 2) repos already attached (TOML front matter in PROJECT.md)
existing="$(HP_PROJECT="$hp_root/$slug/PROJECT.md" python3 - <<'PY'
import os, tomllib
p = os.environ["HP_PROJECT"]
try:
    text = open(p, encoding="utf-8").read()
    if text.startswith("+++"):
        text = text.split("+++", 2)[1]
    for r in tomllib.loads(text).get("repos", []):
        print(os.path.realpath(os.path.expanduser(r.get("path", ""))))
except Exception:
    pass
PY
)"

# 3) pick new repos (multi), skipping attached ones (compare real paths once)
roots="${HP_PROJECT_ROOTS:-$HOME/Documents/workspace}"
list_repos() {
  old_ifs=$IFS
  IFS=:
  for root in $roots; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 4 -type d -name .git -prune 2>/dev/null |
      while IFS= read -r gitdir; do
        printf '%s\n' "${gitdir%/.git}"
      done
  done
  IFS=$old_ifs
}

selection="$(list_repos | sort -u | HP_ATTACHED="$existing" python3 -c '
import os, sys
attached = {os.path.realpath(os.path.expanduser(p))
            for p in os.environ.get("HP_ATTACHED", "").splitlines() if p}
for line in sys.stdin:
    p = line.strip()
    if p and os.path.realpath(os.path.expanduser(p)) not in attached:
        print(p)
' | fzf \
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
  "$hp_bin" --root "$hp_root" set "$slug" repos.add "$repo" \
    || die "'repos.add $repo' failed"
  echo "attached $repo"
done
printf '\n%d repo(s) attached to %s\n' "${#repos[@]}" "$slug"
printf 'press enter to close'
read -r _ || true
