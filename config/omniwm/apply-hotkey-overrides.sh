#!/usr/bin/env bash
# Seed the trial's curated, machine-independent OmniWM keybindings onto the
# app-generated settings.toml. OmniWM owns that file and it is strictly
# validated, so this script only rewrites `binding =` values for a fixed set of
# action ids and fixed machine-independent table scalars; machine-local sections
# (monitor routing, workspace identities) are never touched.
#
# Seed-once per REV: after a successful run a stamp file is written, so later
# activations leave GUI customizations alone. Bump REV when the curated keymap
# changes; OMNIWM_HOTKEY_FORCE=1 reapplies the current revision. OmniWM watches
# the file externally and reloads it while running.
#
# This script is platform-neutral by contract: it performs plain file edits
# and contains no platform privilege or package-manager tooling. The nix-darwin
# module is the thin wrapper that invokes it as the target user.
set -uo pipefail

REV="3"
STAMP_NAME=".hotkey-overrides.rev"
LOG_PREFIX="[omniwm-hotkeys]"

log() { printf '%s %s\n' "$LOG_PREFIX" "$*" >&2; }

# Scalar overrides as "table.key:type:value" specs (type is string, bool or
# float). These are machine-independent GUI preferences folded into the seed
# (not machine-local sections like routing/workspace identities): the Hyper
# trigger pitfall, focus-follows-mouse pointer placement, and the curated
# workspace-bar look (height, hidden empty slots, notch split, transparent).
SCALAR_SPECS=(
  "general.systemHyperTrigger:string:None"
  "focus.moveMouseToFocusedWindow:bool:true"
  "workspaceBar.height:float:26.0"
  "workspaceBar.hideEmptyWorkspaces:bool:true"
  "workspaceBar.inactiveIconOpacity:float:0.85"
  "workspaceBar.notchActiveZoneWidth:float:100.0"
  "workspaceBar.notchMode:string:splitActiveLeft"
  "workspaceBar.showItemBackgrounds:bool:false"
  "workspaceBar.transparentBackground:bool:true"
)

# Curated action id -> binding, using OmniWM's own binding spelling.
# hjkl focus/move (arrows are replaced, one binding per action), niri-style
# comma/period workspace scrolling, and the size-cycle key that frees period.
HOTKEY_IDS=(
  focus.left
  focus.down
  focus.up
  focus.right
  move.left
  move.down
  move.up
  move.right
  toggleWorkspaceLayout
  cycleSizeForward
  cycleSizeBackward
  switchWorkspace.next
  switchWorkspace.previous
  moveWindowToWorkspaceUp
  moveWindowToWorkspaceDown
  moveColumnToWorkspaceUp
  moveColumnToWorkspaceDown
  # Free Control+Option+F: herdr owns the ctrl+alt letter layer (goto picker),
  # and this one-way "eat slack width" action is an obscure niri advanced move.
  expandContainerToAvailablePrimarySpan
)
HOTKEY_BINDINGS=(
  "Option+H"
  "Option+J"
  "Option+K"
  "Option+L"
  "Option+Shift+H"
  "Option+Shift+J"
  "Option+Shift+K"
  "Option+Shift+L"
  "Option+Shift+Slash"
  "Option+R"
  "Unassigned"
  "Option+Period"
  "Option+Comma"
  "Option+Shift+Comma"
  "Option+Shift+Period"
  "Control+Option+Shift+Comma"
  "Control+Option+Shift+Period"
  "Unassigned"
)

if [[ -n "${XDG_CONFIG_HOME:-}" && "${XDG_CONFIG_HOME:0:1}" == "/" ]]; then
  default_config_dir="$XDG_CONFIG_HOME/omniwm"
else
  default_config_dir="$HOME/.config/omniwm"
fi
config_dir="${OMNIWM_CONFIG_DIR:-$default_config_dir}"
settings="$config_dir/settings.toml"
stamp="$config_dir/$STAMP_NAME"

# OmniWM has not generated its configuration yet (first launch is a manual
# step in the trial); nothing to do.
if [[ ! -f "$settings" ]]; then
  log "no settings.toml at $settings; open OmniWM once, then rerun this script."
  exit 0
fi

if [[ "${OMNIWM_HOTKEY_FORCE:-0}" != "1" && -f "$stamp" && "$(cat "$stamp")" == "$REV" ]]; then
  log "revision $REV already applied; leaving GUI-owned settings untouched."
  exit 0
fi

# Defensive validation of the embedded table before interpolating it into awk.
for value in "${HOTKEY_BINDINGS[@]}"; do
  if [[ ! "$value" =~ ^(Unassigned|[A-Za-z0-9\ +]+)$ ]]; then
    log "internal error: unsafe binding '$value'"; exit 1
  fi
done
for id in "${HOTKEY_IDS[@]}"; do
  if [[ ! "$id" =~ ^[A-Za-z0-9.]+$ ]]; then
    log "internal error: unsafe action id '$id'"; exit 1
  fi
done
# Parse and validate the scalar specs (only single-level [table] sections).
SCALAR_TABLES=()
SCALAR_KEYS=()
SCALAR_RENDERED=()
for spec in "${SCALAR_SPECS[@]}"; do
  table="${spec%%.*}"
  rest="${spec#*.}"
  key="${rest%%:*}"
  rest="${rest#*:}"
  type="${rest%%:*}"
  value="${rest#*:}"
  if [[ ! "$table" =~ ^[A-Za-z0-9]+$ || ! "$key" =~ ^[A-Za-z0-9]+$ ]]; then
    log "internal error: unsafe scalar spec '$spec'"; exit 1
  fi
  case "$type" in
    string)
      [[ "$value" =~ ^[A-Za-z0-9\ _.-]+$ ]] || { log "internal error: unsafe string scalar '$spec'"; exit 1; }
      rendered='\"'"$value"'\"'
      ;;
    bool)
      [[ "$value" =~ ^(true|false)$ ]] || { log "internal error: unsafe bool scalar '$spec'"; exit 1; }
      rendered="$value"
      ;;
    float)
      [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || { log "internal error: unsafe float scalar '$spec'"; exit 1; }
      rendered="$value"
      ;;
    *)
      log "internal error: unknown scalar type '$type'"; exit 1
      ;;
  esac
  SCALAR_TABLES+=("$table")
  SCALAR_KEYS+=("$key")
  SCALAR_RENDERED+=("$rendered")
done

backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
cp -p "$settings" "$backup"
# Keep the five newest backups.
while IFS= read -r old; do rm -f "$old"; done < <(
  ls -1t "$settings".bak-* 2>/dev/null | tail -n +6
)
log "backed up to $backup"

tmp="$(mktemp "${settings}.tmp.XXXXXX")"
cleanup() { rm -f "$tmp" "$tmp.trim"; }
trap cleanup EXIT

awk_begin="BEGIN {"
for i in "${!HOTKEY_IDS[@]}"; do
  awk_begin+=$'\n  binding_for["'"${HOTKEY_IDS[$i]}"'"]="'"${HOTKEY_BINDINGS[$i]}"'"'
done
for i in "${!SCALAR_SPECS[@]}"; do
  awk_begin+=$'\n  scalar_for["'"${SCALAR_TABLES[$i]}.${SCALAR_KEYS[$i]}"'"]="'"${SCALAR_RENDERED[$i]}"'"'
done
awk_begin+=$'\n}'

if ! awk "$awk_begin"'
  BEGIN { RS = ""; FS = "\n" }
  {
    is_hotkeys = ($1 == "[[hotkeys]]")
    # Single-level plain table header like "[focus]" (not "[[hotkeys]]" and
    # not a dotted sub-table); spelled without bracket classes for BSD awk.
    is_plain_table = ($1 ~ /^\[/ && $1 !~ /\[\[/ && $1 ~ /\]$/ && index($1, ".") == 0)
    id = ""
    delete out
    for (i = 1; i <= NF; i++) out[i] = $i

    if (is_hotkeys) {
      for (i = 1; i <= NF; i++) {
        if (out[i] ~ /^id = "/) {
          id = out[i]
          sub(/^id = "/, "", id)
          sub(/"$/, "", id)
          break
        }
      }
      if (id in binding_for) {
        for (i = 1; i <= NF; i++) {
          if (out[i] ~ /^binding = /) {
            out[i] = "binding = \"" binding_for[id] "\""
            break
          }
        }
        found[id] = 1
      }
    }

    if (is_plain_table) {
      scope = $1
      sub(/^\[/, "", scope)
      sub(/\]$/, "", scope)
      for (tk in scalar_for) {
        n = split(tk, parts, ".")
        if (n != 2 || parts[1] != scope) continue
        matched = 0
        for (i = 1; i <= NF; i++) {
          rx = "^" parts[2] "[[:space:]]*="
          if (out[i] ~ rx) {
            out[i] = parts[2] " = " scalar_for[tk]
            matched = 1
            break
          }
        }
        # Key absent from this schema table (e.g. a nil default the app
        # omits): append it at the end of the table paragraph.
        if (!matched) {
          out[NF + 1] = parts[2] " = " scalar_for[tk]
          NF = NF + 1
        }
        seen_scalar[tk] = 1
      }
    }

    if (is_hotkeys) {
      for (i = 1; i <= NF; i++) {
        if (out[i] ~ /^binding = "/ && out[i] != "binding = \"Unassigned\"")
          binding_counts[out[i]]++
      }
    }

    for (i = 1; i <= NF; i++) print out[i]
    printf "\n"
  }
  END {
    for (id in binding_for) {
      if (!(id in found))
        print "[omniwm-hotkeys] warning: action id not found in this settings schema: " id > "/dev/stderr"
    }
    for (tk in scalar_for) {
      if (!(tk in seen_scalar))
        print "[omniwm-hotkeys] warning: table scalar not found: " tk > "/dev/stderr"
    }
    conflict = 0
    for (b in binding_counts) {
      if (binding_counts[b] > 1) {
        print "[omniwm-hotkeys] duplicate binding after rewrite: " b > "/dev/stderr"
        conflict = 1
      }
    }
    if (conflict) exit 3
  }
' "$settings" >"$tmp"; then
  log "rewrite failed; restoring backup."
  cp -p "$backup" "$settings"
  exit 1
fi

# awk paragraph mode leaves blank separators; normalize to a single trailing
# newline without touching any other byte.
normalized="$(cat "$tmp")"
printf '%s\n' "$normalized" >"$tmp"

# Stronger validation when a system Python is available: the whole file must
# parse and no two hotkeys may share an assigned binding.
if command -v python3 >/dev/null 2>&1; then
  if ! SETTINGS_PATH="$tmp" python3 - <<'PY'
import os, sys, tomllib
from collections import Counter
with open(os.environ["SETTINGS_PATH"], "rb") as f:
    data = tomllib.load(f)
hotkeys = data.get("hotkeys", [])
counts = Counter(h.get("binding", "Unassigned") for h in hotkeys)
dupes = [b for b, n in counts.items() if n > 1 and b != "Unassigned"]
if dupes:
    print(f"[omniwm-hotkeys] duplicate bindings: {dupes}", file=sys.stderr)
    sys.exit(1)
PY
  then
    log "validation rejected the rewrite; restoring backup."
    cp -p "$backup" "$settings"
    exit 1
  fi
fi

mv "$tmp" "$settings"
trap - EXIT

printf '%s\n' "$REV" >"$stamp"
log "curated keybindings applied (revision $REV); OmniWM reloads settings live."
