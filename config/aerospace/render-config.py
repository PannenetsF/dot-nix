#!/usr/bin/env python3
import ctypes
import json
import os
import platform
import subprocess
import sys
import tempfile
from ctypes import POINTER, byref, c_bool, c_double, c_int32, c_uint32


BEGIN_MARKER = "# BEGIN AUTO-GENERATED WORKSPACE ASSIGNMENTS"
END_MARKER = "# END AUTO-GENERATED WORKSPACE ASSIGNMENTS"
WORKSPACES = tuple(str(index) for index in range(1, 11))
PREFERRED_PRIMARY_MONITOR_NAMES = ("hp z27k g3",)


class CGPoint(ctypes.Structure):
    _fields_ = [("x", c_double), ("y", c_double)]


class CGSize(ctypes.Structure):
    _fields_ = [("width", c_double), ("height", c_double)]


class CGRect(ctypes.Structure):
    _fields_ = [("origin", CGPoint), ("size", CGSize)]


def quote_toml_value(value):
    if isinstance(value, int):
        return str(value)
    escaped = str(value).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def format_assignment(target):
    """Render a single workspace assignment value.

    AeroSpace resolves an array of monitor descriptions to the *first* one that
    matches a connected monitor (see MonitorDescription.swift). We always append
    ``'main'`` as the final fallback so that when the primary monitor is absent
    -- after closing the lid, undocking, or a power-loss reconnect renumbers the
    displays -- the workspace lands on the main monitor instead of being
    stranded on a monitor that no longer exists. ``'main'`` itself never needs a
    fallback because there is always exactly one main monitor.
    """
    if target == "main":
        return "'main'"
    return f"[{quote_toml_value(target)}, 'main']"


def load_displays_from_env():
    raw = os.environ.get("AEROSPACE_MONITORS_JSON")
    if not raw:
        return None

    displays = []
    for item in json.loads(raw):
        displays.append(
            {
                "seq": int(item["seq"]),
                "name": str(item.get("name", "")),
                "main": bool(item.get("main", False)),
                "built_in": bool(item.get("built_in", False)),
            }
        )
    return sorted(displays, key=lambda display: display["seq"])


def load_displays_from_aerospace():
    aerospace = "/opt/homebrew/bin/aerospace"
    if platform.system() != "Darwin" or not os.path.exists(aerospace):
        return None

    try:
        output = subprocess.check_output(
            [
                aerospace,
                "list-monitors",
                "--format",
                "%{monitor-id}\t%{monitor-name}\t%{monitor-is-main}",
            ],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=1,
        )
    except (subprocess.SubprocessError, OSError):
        return None

    displays = []
    for line in output.splitlines():
        parts = line.split("\t", maxsplit=2)
        if len(parts) != 3:
            continue
        monitor_id, monitor_name, is_main = parts
        try:
            seq = int(monitor_id)
        except ValueError:
            continue
        lower_name = monitor_name.lower()
        displays.append(
            {
                "seq": seq,
                "name": monitor_name,
                "main": is_main == "true",
                "built_in": "built-in" in lower_name or "retina display" in lower_name,
            }
        )

    return sorted(displays, key=lambda display: display["seq"]) or None


def load_displays_from_coregraphics():
    if platform.system() != "Darwin":
        return None

    cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
    display_id_type = c_uint32

    cg.CGGetOnlineDisplayList.argtypes = [
        c_uint32,
        POINTER(display_id_type),
        POINTER(c_uint32),
    ]
    cg.CGGetOnlineDisplayList.restype = c_int32
    cg.CGMainDisplayID.argtypes = []
    cg.CGMainDisplayID.restype = display_id_type
    cg.CGDisplayIsBuiltin.argtypes = [display_id_type]
    cg.CGDisplayIsBuiltin.restype = c_bool
    cg.CGDisplayBounds.argtypes = [display_id_type]
    cg.CGDisplayBounds.restype = CGRect

    count = c_uint32()
    if cg.CGGetOnlineDisplayList(0, None, byref(count)) != 0 or count.value == 0:
        return None

    online_displays = (display_id_type * count.value)()
    if cg.CGGetOnlineDisplayList(count.value, online_displays, byref(count)) != 0:
        return None

    main_display_id = cg.CGMainDisplayID()
    displays = []
    for display_id in online_displays[: count.value]:
        bounds = cg.CGDisplayBounds(display_id)
        displays.append(
            {
                "display_id": int(display_id),
                "name": "",
                "x": float(bounds.origin.x),
                "y": float(bounds.origin.y),
                "main": display_id == main_display_id,
                "built_in": bool(cg.CGDisplayIsBuiltin(display_id)),
            }
        )

    displays.sort(key=lambda display: (display["x"], display["y"], display["display_id"]))
    for index, display in enumerate(displays, start=1):
        display["seq"] = index
    return displays


def load_displays():
    env_displays = load_displays_from_env()
    if env_displays is not None:
        return "env", env_displays

    aerospace_displays = load_displays_from_aerospace()
    if aerospace_displays is not None:
        return "aerospace", aerospace_displays

    coregraphics_displays = load_displays_from_coregraphics()
    if coregraphics_displays is not None:
        return "coregraphics", coregraphics_displays

    return "none", []


def assignment_targets(displays):
    if not displays:
        return ["main"]

    primary_display = preferred_primary_display(displays)
    if primary_display is None:
        primary_display = next(
            (display for display in displays if display["main"]), displays[0]
        )

    primary_target = (
        primary_display["seq"]
        if is_preferred_primary_display(primary_display)
        else "main"
    )

    external_targets = []
    built_in_target = None
    for display in displays:
        if display is primary_display:
            continue
        if display["built_in"]:
            built_in_target = "built-in"
            continue
        external_targets.append(display["seq"])

    targets = [primary_target, *external_targets]
    if built_in_target:
        targets.append(built_in_target)

    if len(targets) > len(WORKSPACES):
        if built_in_target:
            targets = targets[: len(WORKSPACES) - 1] + [built_in_target]
        else:
            targets = targets[: len(WORKSPACES)]
    return targets


def is_preferred_primary_display(display):
    name = display.get("name", "").lower()
    return any(preferred in name for preferred in PREFERRED_PRIMARY_MONITOR_NAMES)


def preferred_primary_display(displays):
    return next(
        (display for display in displays if is_preferred_primary_display(display)), None
    )


def distribute(workspaces, targets):
    if not targets:
        return [(workspace, "main") for workspace in workspaces]

    assignments = []
    cursor = 0
    base = len(workspaces) // len(targets)
    remainder = len(workspaces) % len(targets)

    for index, target in enumerate(targets):
        count = base + (1 if index < remainder else 0)
        for workspace in workspaces[cursor : cursor + count]:
            assignments.append((workspace, target))
        cursor += count
    return assignments


def generate_assignment_block(displays):
    assignments = distribute(WORKSPACES, assignment_targets(displays))

    lines = [
        BEGIN_MARKER,
        "# Generated by config/aerospace/render-config.py.",
        "[workspace-to-monitor-force-assignment]",
    ]
    for workspace, target in assignments:
        lines.append(f"{workspace} = {format_assignment(target)}")
    lines.append(END_MARKER)
    return "\n".join(lines)


def replace_generated_block(template, block):
    begin = template.find(BEGIN_MARKER)
    end = template.find(END_MARKER)
    if begin == -1 or end == -1 or end < begin:
        raise ValueError("template is missing AeroSpace workspace assignment markers")
    end += len(END_MARKER)
    return template[:begin] + block + template[end:]


def extract_generated_block(content):
    begin = content.find(BEGIN_MARKER)
    end = content.find(END_MARKER)
    if begin == -1 or end == -1 or end < begin:
        return None
    end += len(END_MARKER)
    return content[begin:end]


def assignment_block_has_external_targets(block):
    for line in block.splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        _, value = line.split("=", maxsplit=1)
        if value.strip() != "'main'":
            return True
    return False


def assignment_state_path(output_path):
    return f"{output_path}.assignments.json"


def load_assignment_state(output_path):
    try:
        with open(assignment_state_path(output_path), encoding="utf-8") as state_file:
            state = json.load(state_file)
    except (OSError, json.JSONDecodeError):
        return None
    return state if isinstance(state, dict) else None


def should_preserve_existing_block(source, displays, output_path):
    if not os.path.exists(output_path):
        return False

    try:
        with open(output_path, "r", encoding="utf-8") as output_file:
            existing_block = extract_generated_block(output_file.read())
    except OSError:
        return False

    if existing_block is None:
        return False

    assignments = load_assignment_state(output_path)

    # CoreGraphics can confirm that displays exist, but its left-to-right
    # sequence is not AeroSpace's monitor index and it has no monitor names.
    # Preserve the last authoritative mapping until AeroSpace is queryable.
    # An AeroSpace/env snapshot is authoritative even when it has fewer
    # displays: a stable unplugged topology must replace stale numeric IDs.
    if assignments is not None:
        return source not in ("aerospace", "env")

    # Compatibility for the first activation after upgrading from the older
    # renderer, before the structured assignment sidecar has been created.
    return (
        source == "coregraphics"
        and len(displays) == 1
        and assignment_block_has_external_targets(existing_block)
    )


def assignment_patterns(target):
    return [target] if target == "main" else [target, "main"]


def generate_assignments(displays):
    return {
        workspace: assignment_patterns(target)
        for workspace, target in distribute(WORKSPACES, assignment_targets(displays))
    }


def atomic_write(path, content):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".aerospace.", suffix=".toml", dir=directory)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
            tmp_file.write(content)
            if not content.endswith("\n"):
                tmp_file.write("\n")
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def atomic_write_json(path, value):
    atomic_write(path, json.dumps(value, indent=2, sort_keys=True))


def main(argv):
    if len(argv) != 3:
        print("usage: render-config.py TEMPLATE OUTPUT", file=sys.stderr)
        return 2

    template_path, output_path = argv[1:]
    with open(template_path, "r", encoding="utf-8") as template_file:
        template = template_file.read()

    source, displays = load_displays()
    if should_preserve_existing_block(source, displays, output_path):
        with open(output_path, "r", encoding="utf-8") as output_file:
            existing_block = extract_generated_block(output_file.read())
        rendered = replace_generated_block(template, existing_block)
        assignments = load_assignment_state(output_path)
    else:
        rendered = replace_generated_block(template, generate_assignment_block(displays))
        assignments = generate_assignments(displays)
    atomic_write(output_path, rendered)
    if assignments is not None:
        atomic_write_json(assignment_state_path(output_path), assignments)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
