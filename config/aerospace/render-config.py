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


def load_displays_from_env():
    raw = os.environ.get("AEROSPACE_MONITORS_JSON")
    if not raw:
        return None

    displays = []
    for item in json.loads(raw):
        displays.append(
            {
                "seq": int(item["seq"]),
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

    external_targets = []
    built_in_target = None
    for display in displays:
        if display["main"]:
            continue
        if display["built_in"]:
            built_in_target = "built-in"
            continue
        external_targets.append(display["seq"])

    targets = ["main", *external_targets]
    if built_in_target:
        targets.append(built_in_target)

    if len(targets) > len(WORKSPACES):
        if built_in_target:
            targets = targets[: len(WORKSPACES) - 1] + [built_in_target]
        else:
            targets = targets[: len(WORKSPACES)]
    return targets


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
        lines.append(f"{workspace} = {quote_toml_value(target)}")
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


def should_preserve_existing_block(source, displays, output_path):
    if source != "coregraphics" or len(displays) != 1 or not os.path.exists(output_path):
        return False

    try:
        with open(output_path, "r", encoding="utf-8") as output_file:
            existing_block = extract_generated_block(output_file.read())
    except OSError:
        return False

    return existing_block is not None and assignment_block_has_external_targets(existing_block)


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
    else:
        rendered = replace_generated_block(template, generate_assignment_block(displays))
    atomic_write(output_path, rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
