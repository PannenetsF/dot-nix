#!/usr/bin/env bash
# claude trust shim — pre-accepts Claude Code's "Do you trust the files in this
# folder?" dialog before the real binary starts, so sessions launched in fresh
# folders (new herdr-projects threads, coordinator-spawned agents) never block
# on the interactive trust prompt.
#
# The dialog has no settings.json / env switch: accepting it just flips
# projects["<workspace-root>"].hasTrustDialogAccepted to true in
# ~/.claude.json (Claude Code docs, "Project allow rules and workspace
# trust"). This wrapper performs that write itself. Roots seeded:
#   - the current directory (non-git folders key trust on the start dir)
#   - the git repository root, when inside one
#   - the main checkout root, when cwd is a linked worktree (Claude keys
#     worktree trust on the main checkout)
# Everything else passes through unchanged; a failed write must never stop
# Claude from launching.
#
# Installed at ~/.local/bin/claude-shim/claude; modules/common.nix prepends
# that directory to PATH so it wins over /opt/homebrew/bin/claude.
set -euo pipefail

# ---- locate the real binary, skipping our own shim directory ---------------
shim_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
real_claude=""
while IFS= read -r _d; do
  [ -n "$_d" ] || continue
  [ "$_d" = "$shim_dir" ] && continue
  if [ -x "$_d/claude" ]; then
    real_claude="$_d/claude"
    break
  fi
done <<< "${PATH//:/$'\n'}"
unset _d
if [ -z "$real_claude" ]; then
  echo "claude-shim: real claude binary not found on PATH" >&2
  exit 127
fi

# ---- preseed the trust flag (interactive sessions only; best effort) --------
# The dialog only exists in interactive sessions; `-p`/SDK runs are non-tty.
if [ -t 0 ] && [ -t 1 ]; then
  # Physical cwd: on macOS /var is a symlink to /private/var, and git reports
  # canonical paths, so $PWD would write a key that never matches.
  roots="$(pwd -P)"
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$git_root" ]; then
    roots="$roots
$git_root"
    # Linked worktree: a non-absolute git-common-dir is relative to cwd, not to
    # the toplevel; ask git for the absolute form (git >= 2.31). In a linked
    # worktree it points at the MAIN checkout's <root>/.git (the current-dir
    # git dir is <main>/.git/worktrees/<wt>), so stripping /.git seeds the main
    # checkout root that Claude keys worktree trust against.
    if common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
       && [ -n "$common" ]; then
      common="${common%/}"
      case "$common" in
        */.git) roots="$roots
${common%/.git}" ;;
      esac
    fi
  fi

  config_file="$HOME/.claude.json"
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r root; do
      [ -n "$root" ] || continue
      tmp="${config_file}.tmp.$$"
      { [ -s "$config_file" ] && cat "$config_file" || echo '{}'; } \
        | jq --arg p "$root" '.projects[$p].hasTrustDialogAccepted = true' \
        > "$tmp" 2>/dev/null && mv "$tmp" "$config_file" || rm -f "$tmp"
    done <<< "$roots"
  elif command -v python3 >/dev/null 2>&1; then
    CLAUDE_TRUST_ROOTS="$roots" CLAUDE_TRUST_FILE="$config_file" \
      python3 -I - <<'PY' 2>/dev/null || true
import json, os
path = os.environ["CLAUDE_TRUST_FILE"]
roots = {r for r in os.environ["CLAUDE_TRUST_ROOTS"].splitlines() if r}
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
projects = data.setdefault("projects", {})
changed = False
for root in roots:
    entry = projects.get(root)
    if not isinstance(entry, dict) or not entry.get("hasTrustDialogAccepted"):
        entry = entry if isinstance(entry, dict) else {}
        entry["hasTrustDialogAccepted"] = True
        projects[root] = entry
        changed = True
if changed:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
PY
  fi
  unset config_file roots git_root common common_abs
fi

# ---- hand off to the real binary --------------------------------------------
exec -a claude "$real_claude" "$@"
