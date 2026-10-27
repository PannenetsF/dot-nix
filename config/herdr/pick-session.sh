#!/usr/bin/env bash
# Human-session picker; Portal owns the shared local/remote thread classifier.
set -euo pipefail
self="${BASH_SOURCE[0]}"
if target="$(readlink "$self" 2>/dev/null)" && [ -n "$target" ]; then self="$target"; fi
case "$self" in /*) ;; *) self="$(cd "$(dirname "$self")" && pwd)/$(basename "$self")" ;; esac
. "$(dirname "$self")/herdr-popup-lib.sh"
herdr_popup_prepend_path
command -v fzf >/dev/null 2>&1 || die "fzf not found on PATH"
board="$(python3 - <<'PY'
import json, os
from pathlib import Path
config = Path(os.environ.get('HERDR_CONFIG_DIR', str(Path.home() / '.config/herdr')))
registry = json.loads((config / 'plugins.json').read_text())
portal = next(p for p in registry if p['plugin_id'] == 'herdr-portal' and p.get('enabled') is not False)
board = Path(portal['plugin_root']) / 'board'
if not (board / 'dot_nix_portal_policy.py').is_file():
    raise SystemExit('Portal session policy missing; install Herdr plugins first')
print(board)
PY
)"
exec python3 "$board/dot_nix_portal_policy.py" --pick "$board"
