#!/usr/bin/env python3
import json
import subprocess
import sys


WORKSPACES = tuple(str(index) for index in range(1, 11))


def run(cli, *arguments, capture=False):
    return subprocess.run(
        [cli, *arguments],
        check=False,
        text=True,
        capture_output=capture,
    )


def load_assignments(assignments_path):
    with open(assignments_path, encoding="utf-8") as assignments_file:
        raw_assignments = json.load(assignments_file)

    assignments = {}
    for workspace in WORKSPACES:
        targets = raw_assignments[workspace]
        if not isinstance(targets, list) or not targets:
            raise ValueError(f"workspace {workspace} has no monitor targets")
        assignments[workspace] = [str(target) for target in targets]
    return assignments


def query_focused_workspace(cli):
    result = run(
        cli,
        "list-workspaces",
        "--focused",
        "--format",
        "%{workspace}",
        capture=True,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def query_workspace_states(cli):
    result = run(
        cli,
        "list-workspaces",
        "--all",
        "--format",
        "%{workspace}\t%{monitor-id}\t%{workspace-is-visible}",
        capture=True,
    )
    if result.returncode != 0:
        return None

    states = {}
    for line in result.stdout.splitlines():
        parts = line.split("\t", maxsplit=2)
        if len(parts) == 3:
            states[parts[0]] = (parts[1], parts[2] == "true")
    return states


def activate_missing_monitor_workspaces(cli, states):
    workspaces_by_monitor = {}
    visible_monitors = set()
    for workspace in WORKSPACES:
        state = states.get(workspace)
        if state is None:
            continue
        monitor, visible = state
        workspaces_by_monitor.setdefault(monitor, []).append(workspace)
        if visible:
            visible_monitors.add(monitor)

    for monitor, workspaces in workspaces_by_monitor.items():
        if monitor not in visible_monitors:
            result = run(cli, "workspace", workspaces[0])
            if result.returncode != 0:
                return False
    return True


def main(argv):
    if len(argv) != 3:
        print("usage: rehome-workspaces.py ASSIGNMENTS_JSON AEROSPACE_CLI", file=sys.stderr)
        return 2

    assignments_path, cli = argv[1:]
    try:
        assignments = load_assignments(assignments_path)
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        print(f"rehome-aerospace: cannot read assignments: {error}", file=sys.stderr)
        return 1

    focused_workspace = query_focused_workspace(cli)
    failed = False
    for workspace, targets in assignments.items():
        result = run(
            cli,
            "move-workspace-to-monitor",
            "--workspace",
            workspace,
            *targets,
        )
        if result.returncode != 0:
            failed = True

    if failed:
        print("rehome-aerospace: one or more workspace moves failed", file=sys.stderr)
        return 1

    states = query_workspace_states(cli)
    if states is None or not activate_missing_monitor_workspaces(cli, states):
        print("rehome-aerospace: could not activate target workspaces", file=sys.stderr)
        return 1

    current_workspace = query_focused_workspace(cli)
    if focused_workspace in WORKSPACES and current_workspace != focused_workspace:
        if run(cli, "workspace", focused_workspace).returncode != 0:
            print("rehome-aerospace: could not restore focused workspace", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
