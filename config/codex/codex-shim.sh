#!/usr/bin/env bash
# codex trust shim — pre-accepts Codex's per-folder trust dialog before the
# real binary starts, so sessions in fresh herdr-projects worktrees do not stop
# before receiving their brief. Like the Claude shim, it seeds the physical
# cwd, the repository root, and the main checkout of a linked worktree.
#
# Only projects["<root>"].trust_level is set. Command approvals, the sandbox,
# and hook trust are unchanged; this is NOT --dangerously-bypass-approvals-and-
# sandbox or --dangerously-bypass-hook-trust.
#
# Installed at ~/.local/bin/codex-shim/codex and prepended to PATH by
# modules/common.nix. CODEX_HOME and non-interactive invocations are respected.
set -euo pipefail

# ---- locate the real binary, skipping our own shim directory ---------------
shim_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
real_codex=""
while IFS= read -r _d; do
  [ -n "$_d" ] || continue
  [ "$_d" = "$shim_dir" ] && continue
  if [ -x "$_d/codex" ]; then
    real_codex="$_d/codex"
    break
  fi
done <<< "${PATH//:/$'\n'}"
unset _d
if [ -z "$real_codex" ]; then
  echo "codex-shim: real codex binary not found on PATH" >&2
  exit 127
fi

# ---- preseed directory trust (interactive sessions only; best effort) ------
if [ -t 0 ] && [ -t 1 ] && command -v python3 >/dev/null 2>&1; then
  roots="$(pwd -P)"
  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$git_root" ]; then
    roots="$roots
$git_root"
    if common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
       && [ -n "$common" ]; then
      common="${common%/}"
      case "$common" in
        */.git) roots="$roots
${common%/.git}" ;;
      esac
    fi
  fi

  # Append only missing entries instead of serializing the whole TOML document:
  # Codex's config also contains hook trust hashes and user-owned comments.
  # Validate first, preserve the existing mode, and never block launch on error.
  CODEX_TRUST_ROOTS="$roots" CODEX_TRUST_FILE="${CODEX_HOME:-$HOME/.codex}/config.toml" \
    python3 -I - <<'PY' 2>/dev/null || true
import fcntl
import json
import os
import stat
import tomllib

path = os.environ["CODEX_TRUST_FILE"]
roots = {r for r in os.environ["CODEX_TRUST_ROOTS"].splitlines() if r}
os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
with open(path + ".trust-shim.lock", "a+", encoding="utf-8") as lock:
    os.chmod(lock.name, 0o600)
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        with open(path, encoding="utf-8") as config:
            text = config.read()
    except FileNotFoundError:
        text = ""
    data = tomllib.loads(text) if text.strip() else {}
    projects = data.get("projects", {})
    if not isinstance(projects, dict):
        raise TypeError("Codex projects config is not a table")
    # An existing entry belongs to the user; in particular, never overwrite an
    # explicit untrusted value. Fresh worktrees are the case this shim handles.
    additions = [root for root in sorted(roots) if root not in projects]
    if additions:
        block = "".join(
            f"\n[projects.{json.dumps(root, ensure_ascii=False)}]\n"
            'trust_level = "trusted"\n'
            for root in additions
        )
        candidate = text.rstrip() + "\n" + block
        tomllib.loads(candidate)
        mode = stat.S_IMODE(os.stat(path).st_mode) if os.path.exists(path) else 0o600
        tmp = f"{path}.tmp.{os.getpid()}"
        try:
            with open(tmp, "x", encoding="utf-8") as out:
                os.chmod(tmp, mode)
                out.write(candidate)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
PY
  unset roots git_root common
fi

# ---- hand off to the real binary --------------------------------------------
exec -a codex "$real_codex" "$@"
