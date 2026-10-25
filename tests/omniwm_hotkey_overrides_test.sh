#!/usr/bin/env bash
# Stubbed tests for config/omniwm/apply-hotkey-overrides.sh: never touches the
# real ~/.config/omniwm, never starts/stops anything.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/config/omniwm/apply-hotkey-overrides.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

config_dir="$tmp/omniwm"
mkdir -p "$config_dir"
settings="$config_dir/settings.toml"
stamp="$config_dir/.hotkey-overrides.rev"

# A strict-TOML fixture: root scalars (including the first-launch Hyper pitfall),
# a gestures table, all targeted hotkeys, decoy hotkeys, and machine-local
# sections that must survive byte-for-byte.
cat >"$settings" <<'TOML'
monitorBarOverrides = []

[general]
hotkeysEnabled = true
hyperKeyModifiers = "Control+Option+Shift+Command"
systemHyperTrigger = "Left Option"
updateChecksEnabled = true

[focus]
followsMouse = false
moveMouseToFocusedWindow = false

[workspaceBar]
height = 24.0
hideEmptyWorkspaces = false
notchActiveZoneWidth = 180.0
notchMode = "moveBelowMenuBar"
showItemBackgrounds = true
transparentBackground = false
# inactiveIconOpacity intentionally omitted: a nil default OmniWM leaves out
# of the file; the seed must append it rather than silently skip it.

[gestures]
scrollEnabled = true

[[hotkeys]]
binding = "Option+Left Arrow"
id = "focus.left"

[[hotkeys]]
binding = "Option+Down Arrow"
id = "focus.down"

[[hotkeys]]
binding = "Option+Up Arrow"
id = "focus.up"

[[hotkeys]]
binding = "Option+Right Arrow"
id = "focus.right"

[[hotkeys]]
binding = "Option+Shift+Left Arrow"
id = "move.left"

[[hotkeys]]
binding = "Option+Shift+Down Arrow"
id = "move.down"

[[hotkeys]]
binding = "Option+Shift+Up Arrow"
id = "move.up"

[[hotkeys]]
binding = "Option+Shift+Right Arrow"
id = "move.right"

[[hotkeys]]
binding = "Option+Shift+L"
id = "toggleWorkspaceLayout"

[[hotkeys]]
binding = "Option+Period"
id = "cycleSizeForward"

[[hotkeys]]
binding = "Option+Comma"
id = "cycleSizeBackward"

[[hotkeys]]
binding = "Unassigned"
id = "switchWorkspace.next"

[[hotkeys]]
binding = "Unassigned"
id = "switchWorkspace.previous"

[[hotkeys]]
binding = "Control+Option+Shift+Up Arrow"
id = "moveWindowToWorkspaceUp"

[[hotkeys]]
binding = "Control+Option+Shift+Down Arrow"
id = "moveWindowToWorkspaceDown"

[[hotkeys]]
binding = "Control+Option+Shift+Page Up"
id = "moveColumnToWorkspaceUp"

[[hotkeys]]
binding = "Control+Option+Shift+Page Down"
id = "moveColumnToWorkspaceDown"

[[hotkeys]]
binding = "Control+Option+F"
id = "expandContainerToAvailablePrimarySpan"

[[hotkeys]]
binding = "Option+Tab"
id = "focusPrevious"

[[hotkeys]]
binding = "Option+1"
id = "switchWorkspace.0"

[routing]

[[routing.arrangements]]
[[routing.arrangements.monitors]]
monitorDisplayUUID = "MACHINE-LOCAL-UUID-MUST-STAY"
monitorName = "MACHINE-LOCAL-MONITOR-NAME"

[[workspaces]]
id = "MACHINE-LOCAL-WORKSPACE-UUID"
name = "1"

[workspaces.monitorAssignment]
type = "main"
TOML

# --- missing settings file: skip cleanly ------------------------------------
missing_dir="$tmp/missing/omniwm"
mkdir -p "$missing_dir"
if ! OMNIWM_CONFIG_DIR="$missing_dir" bash "$script" >"$tmp/out" 2>&1; then
  echo "missing settings must not fail" >&2; exit 1
fi
grep -q "no settings.toml" "$tmp/out"
[[ ! -e "$missing_dir/.hotkey-overrides.rev" ]]

# --- first application -------------------------------------------------------
check_expected() {
  SETTINGS_PATH="$settings" python3 - <<'PY'
import os, tomllib
from collections import Counter
with open(os.environ["SETTINGS_PATH"], "rb") as f:
    cfg = tomllib.load(f)
assert cfg["general"]["systemHyperTrigger"] == "None", cfg["general"]["systemHyperTrigger"]
# Curated GUI-preference scalars (REV 3), across several tables.
assert cfg["focus"]["moveMouseToFocusedWindow"] is True
wb = cfg["workspaceBar"]
assert wb["height"] == 26.0
assert wb["hideEmptyWorkspaces"] is True
assert abs(wb["inactiveIconOpacity"] - 0.85) < 1e-9
assert wb["notchActiveZoneWidth"] == 100.0
assert wb["notchMode"] == "splitActiveLeft"
assert wb["showItemBackgrounds"] is False
assert wb["transparentBackground"] is True
# Unrelated [general] scalars and root tables must survive untouched.
assert cfg["general"]["hotkeysEnabled"] is True
assert cfg["general"]["hyperKeyModifiers"] == "Control+Option+Shift+Command"
assert cfg["general"]["updateChecksEnabled"] is True
assert cfg["monitorBarOverrides"] == []
assert cfg["gestures"]["scrollEnabled"] is True
expected = {
    "focus.left": "Option+H",
    "focus.down": "Option+J",
    "focus.up": "Option+K",
    "focus.right": "Option+L",
    "move.left": "Option+Shift+H",
    "move.down": "Option+Shift+J",
    "move.up": "Option+Shift+K",
    "move.right": "Option+Shift+L",
    "toggleWorkspaceLayout": "Option+Shift+Slash",
    "cycleSizeForward": "Option+R",
    "cycleSizeBackward": "Unassigned",
    "switchWorkspace.next": "Option+Period",
    "switchWorkspace.previous": "Option+Comma",
    "moveWindowToWorkspaceUp": "Option+Shift+Comma",
    "moveWindowToWorkspaceDown": "Option+Shift+Period",
    "moveColumnToWorkspaceUp": "Control+Option+Shift+Comma",
    "moveColumnToWorkspaceDown": "Control+Option+Shift+Period",
    # ctrl+alt layer belongs to herdr (goto picker).
    "expandContainerToAvailablePrimarySpan": "Unassigned",
}
got = {h["id"]: h["binding"] for h in cfg["hotkeys"]}
for action, binding in expected.items():
    assert got.get(action) == binding, f"{action}: {got.get(action)!r} != {binding!r}"
# Decoy bindings stay.
assert got["focusPrevious"] == "Option+Tab"
assert got["switchWorkspace.0"] == "Option+1"
# No duplicate assigned bindings.
counts = Counter(b for b in got.values() if b != "Unassigned")
dupes = [b for b, n in counts.items() if n > 1]
assert not dupes, dupes
# Machine-local sections are preserved.
text = open(os.environ["SETTINGS_PATH"], encoding="utf-8").read()
for marker in (
    "MACHINE-LOCAL-UUID-MUST-STAY",
    "MACHINE-LOCAL-MONITOR-NAME",
    "MACHINE-LOCAL-WORKSPACE-UUID",
):
    assert marker in text, marker
PY
}

OMNIWM_CONFIG_DIR="$config_dir" bash "$script" >"$tmp/out" 2>&1
cat "$tmp/out"
[[ "$(cat "$stamp")" == "3" ]]
check_expected
ls "$settings".bak-* >/dev/null

# --- idempotent: stamp prevents a second rewrite -----------------------------
cp "$settings" "$tmp/before-second-run"
OMNIWM_CONFIG_DIR="$config_dir" bash "$script" >"$tmp/out" 2>&1
grep -q "already applied" "$tmp/out"
cmp -s "$settings" "$tmp/before-second-run"

# --- a GUI edit survives a stamped activation run ... ------------------------
python3 - <<PY
p = "$settings"
s = open(p, encoding="utf-8").read()
s = s.replace(
    'binding = "Option+H"\nid = "focus.left"',
    'binding = "Option+Left Arrow"\nid = "focus.left"',
)
open(p, "w", encoding="utf-8").write(s)
PY
OMNIWM_CONFIG_DIR="$config_dir" bash "$script" >/dev/null 2>&1
grep -B1 'id = "focus.left"' "$settings" | grep -q 'Option+Left Arrow'

# ... until the revision is forced.
OMNIWM_HOTKEY_FORCE=1 OMNIWM_CONFIG_DIR="$config_dir" bash "$script" >/dev/null 2>&1
check_expected

# --- old revision stamp re-applies the new curated map -----------------------
printf '0\n' >"$stamp"
python3 - <<PY
p = "$settings"
s = open(p, encoding="utf-8").read()
s = s.replace(
    'binding = "Option+H"\nid = "focus.left"',
    'binding = "Option+Left Arrow"\nid = "focus.left"',
)
open(p, "w", encoding="utf-8").write(s)
PY
OMNIWM_CONFIG_DIR="$config_dir" bash "$script" >/dev/null 2>&1
check_expected

# --- schema drift: a missing id warns but does not fail ----------------------
drift_dir="$tmp/drift/omniwm"
mkdir -p "$drift_dir"
cat >"$drift_dir/settings.toml" <<'TOML'
[general]
systemHyperTrigger = "Left Option"

[[hotkeys]]
binding = "Option+Left Arrow"
id = "focus.left"
TOML
if ! OMNIWM_CONFIG_DIR="$drift_dir" bash "$script" >"$tmp/drift-out" 2>&1; then
  echo "missing action id must not fail the run" >&2; exit 1
fi
grep -q "action id not found" "$tmp/drift-out"
grep -q "table scalar not found: focus.moveMouseToFocusedWindow" "$tmp/drift-out"
grep -B1 'id = "focus.left"' "$drift_dir/settings.toml" | grep -q 'Option+H'
grep -q 'systemHyperTrigger = "None"' "$drift_dir/settings.toml"

# --- conflict with an existing unrelated binding: restore and fail ----------
conflict_dir="$tmp/conflict/omniwm"
mkdir -p "$conflict_dir"
cat >"$conflict_dir/settings.toml" <<'TOML'
[general]
systemHyperTrigger = "None"

[[hotkeys]]
binding = "Option+R"
id = "someFutureAction"

[[hotkeys]]
binding = "Option+Period"
id = "cycleSizeForward"
TOML
cp "$conflict_dir/settings.toml" "$tmp/conflict-original"
if OMNIWM_CONFIG_DIR="$conflict_dir" bash "$script" >"$tmp/conflict-out" 2>&1; then
  echo "duplicate binding must fail and restore" >&2; exit 1
fi
grep -q "duplicate binding" "$tmp/conflict-out"
cmp -s "$conflict_dir/settings.toml" "$tmp/conflict-original"
[[ ! -e "$conflict_dir/.hotkey-overrides.rev" ]]

# --- platform-neutrality and hygiene ----------------------------------------
if grep -En 'launchctl|chown|homebrew|/Users/|bytedance|G27M7Pro' "$script"; then
  echo "script must stay platform/machine-neutral" >&2; exit 1
fi

echo 'OmniWM hotkey override checks passed'
