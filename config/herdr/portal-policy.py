"""Human-session projection for Portal and unread-jump; stdlib only."""

from __future__ import annotations

import json
import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import threading
import time


def visible(pane, agent=None):
    row = {**pane, **(agent or {})}
    tokens = {**pane.get("tokens", {}), **(agent or {}).get("tokens", {})}
    name = row.get("name") or ""
    if tokens.get("hp_role") == "coordinator" or name.startswith("hpc-"):
        return True
    if tokens.get("hp_role") == "thread" or re.match(r"^hp-.+-t-\d+", name):
        return False
    if re.match(r"^[^~!]+!1!", str(tokens.get("hp_group") or "")):
        return False
    if tokens.get("dn_session") == "thread":
        return False
    for cwd in (row.get("cwd"), row.get("foreground_cwd")):
        if cwd and re.search(r"/(?:threads/t-\d+(?:/|$)|\.herdr-project/|[^/]*hp-[^/]*-t-\d+)", cwd):
            return False
    # dn_session is written by the same classifier as the Agents sidebar.
    # Missing tokens must not hide a newly started ordinary remote session.
    return True


def project_parts(parts):
    result = []
    for part in parts:
        part = {**part}
        snapshot = part.get("snapshot")
        if snapshot:
            snapshot = {**snapshot}
            agents = {a["pane_id"]: a for a in snapshot.get("agents", [])}
            panes = [p for p in snapshot.get("panes", []) if visible(p, agents.get(p.get("pane_id")))]
            snapshot["panes"] = panes
            snapshot["agents"] = [a for a in agents.values() if visible(a)]
            part["snapshot"] = snapshot
        result.append(part)
    return result


def install(c):
    if getattr(c, "_human_policy", False):
        return
    c._human_policy = True
    c.COLLECT_TTL = 0.25
    c.collect_or_error.__defaults__ = (c.COLLECT_TTL,)
    original_assemble = c.assemble_snapshot
    original_normalize = c.normalize_item
    original_seen = c.update_seen
    original_focus = c.focus_target
    runtime = c.runtime_dir()
    remote_file = runtime / "human-remotes.json"
    extras_file = runtime / "human-extras.json"
    remote_started = False
    remote_cache_loaded = False
    extras_process = None
    extras_at = 0.0
    cache_lock = threading.Lock()

    def merge_seen(raw):
        if not isinstance(raw, dict):
            return
        for machine, seqs in raw.items():
            if not isinstance(seqs, dict):
                continue
            bucket = c._seen.setdefault(machine, {})
            for pane, seq in seqs.items():
                if isinstance(seq, int) and not isinstance(seq, bool):
                    bucket[pane] = max(bucket.get(pane, seq), seq)

    def load_seen():
        with c._MEMO_LOCK:
            merge_seen(read_cache(c._seen_path()))
            c._seen_loaded = True

    def save_seen(now, force=False):
        with c._MEMO_LOCK:
            if not force and now - c._seen_saved_at < 2:
                return
            file = c._seen_path()
            file.parent.mkdir(parents=True, exist_ok=True)
            # Web, TUI and P-u share this store. Merge under a process lock
            # rather than overwriting another client's acknowledgements.
            with open(file.with_suffix('.lock'), 'a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                merge_seen(read_cache(file))
                atomic_json(file, c._seen)
            c._seen_saved_at = now

    c._load_seen = load_seen
    c._save_seen = save_seen

    def read_cache(file):
        try:
            return json.loads(file.read_text())
        except (OSError, ValueError):
            return {}

    def normalize(*args, **kwargs):
        item = original_normalize(*args, **kwargs)
        item["dn_session"] = "manual"
        # hp_audience=internal is stamped on ALL unregistered panes by the
        # projects ticker; it must not suppress a person's ordinary session.
        item["hp_group"] = item.get("hp_group") or "manual"
        if item.get("status") in {"blocked", "done"}:
            item["hp_audience"] = "human"
        return item

    c.normalize_item = normalize

    def attention(item, seen):
        if item.get("kind") != "agent":
            return False
        if item.get("status") not in {"blocked", "done"} and item.get("hp_audience") not in {"human", "stalled"}:
            return False
        seq = item.get("state_change_seq")
        if not isinstance(seq, int):
            return False
        previous = seen.get(item.get("machine") or c.LOCAL, {}).get(item.get("pane_id"))
        return previous is None or seq > previous

    c.hp_attention_eligible = attention

    def assemble(parts, now=None, **kwargs):
        kwargs["legacy_data"] = {}  # No virtual/restartable worker cards.
        return original_assemble(project_parts(parts), now, **kwargs)

    c.assemble_snapshot = assemble

    def update_seen(parts, now=None):
        # A remote server remembers its last focused pane even while the
        # person is on Local. Do not silently mark those remote cards read.
        return original_seen([p for p in parts if c.is_local(p.get("machine"))], now)

    c.update_seen = update_seen

    def focus(pane_id, machine=None):
        result = original_focus(pane_id, machine)
        snapshot = c.collect_or_error()
        item = c.find_item(snapshot, pane_id, machine)
        if item and isinstance(item.get("state_change_seq"), int):
            with c._MEMO_LOCK:
                c._load_seen()
                c._seen.setdefault(machine or c.LOCAL, {})[pane_id] = item["state_change_seq"]
                c._save_seen(time.time(), force=True)
        return result

    c.focus_target = focus

    def fetch_remote(label):
        c._fetch_remote(label)
        with c._remote_lock:
            data = {label: {k: v for k, v in state.items() if k != "inflight"}
                    for label, state in c._remote_states.items()}
        with cache_lock:
            atomic_json(remote_file, data)

    def remote_loop():
        nonlocal remote_cache_loaded
        while True:
            try:
                rows = c.machine_rows()
                wanted = {str(r["label"]) for r in rows if c._machine_enabled(r) and not c.is_local(r["label"])}
                with c._remote_lock:
                    if not remote_cache_loaded:
                        c._remote_states.update({k: v for k, v in read_cache(remote_file).items() if k in wanted})
                        remote_cache_loaded = True
                    for label in list(c._remote_states):
                        if label not in wanted:
                            del c._remote_states[label]
                    for label in wanted:
                        state = c._remote_states.setdefault(label, {})
                        if not state.get("inflight") and time.time() - state.get("tried_at", 0) >= 1.0:
                            state["inflight"] = True
                            threading.Thread(target=fetch_remote, args=(label,), daemon=True).start()
            except Exception as exc:
                c.note("human session remote refresh", exc)
            time.sleep(0.25)

    def extras():
        nonlocal extras_process, extras_at
        if time.monotonic() - extras_at > 60 and (extras_process is None or extras_process.poll() is not None):
            extras_at = time.monotonic()
            extras_process = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "--extras", str(Path(c.__file__).parent), str(extras_file)],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
            )
        return read_cache(extras_file)

    def collect():
        nonlocal remote_started
        started = time.monotonic()
        now = time.time()
        local = c.run_herdr("api", "snapshot").get("result", {}).get("snapshot", {})
        # Same-host TUI/web processes reuse the last remote snapshot on their
        # first frame; its real ok_at still controls offline/stale protection.
        with c._remote_lock:
            if not c._remote_states:
                c._remote_states.update(read_cache(remote_file))
        c.track_pane_activity(local.get("panes", []), now)
        if not remote_started and os.environ.get("HERDR_PORTAL_REMOTE", "1") != "0":
            remote_started = True
            threading.Thread(target=remote_loop, daemon=True, name="human-remotes").start()
        parts = [{"machine": c.LOCAL, "snapshot": local, "status": "live", "stale": False}]
        if os.environ.get("HERDR_PORTAL_REMOTE", "1") != "0":
            parts.extend(c.remote_parts(now))
        c.update_seen(parts, now)
        extra = extras()
        result = c.assemble_snapshot(parts, now, usage=extra.get("usage"), plan=extra.get("plan"))
        result["collection_ms"] = round((time.monotonic() - started) * 1000, 1)
        return result

    c.collect = collect


def atomic_json(file, data):
    file.parent.mkdir(parents=True, exist_ok=True)
    temp = file.with_name(f"{file.name}.{os.getpid()}.{threading.get_ident()}.tmp")
    try:
        with open(temp, "w", opener=lambda p, flags: os.open(p, flags, 0o600)) as stream:
            json.dump(data, stream)
        temp.replace(file)
    finally:
        temp.unlink(missing_ok=True)


def install_tui(t):
    """Keep remote sessions discoverable even below a long local column."""
    if getattr(t.Board, "_human_machine_filter", False):
        return
    t.Board._human_machine_filter = True
    original_items = t.Board.column_items

    def column_items(self, key):
        items = original_items(self, key)
        machine = getattr(self, "machine_filter", None)
        return [item for item in items if not machine or (item.get("machine") or "Local") == machine]

    def machine_scope_label(self):
        return f"[{getattr(self, 'machine_filter', None) or 'ALL'}] F:machine"

    def cycle_machine(self):
        labels = sorted({str(row["label"]) for row in self.snapshot.get("machines", []) if row.get("label")})
        choices = [None, *labels]
        current = getattr(self, "machine_filter", None)
        index = choices.index(current) if current in choices else -1
        self.machine_filter = choices[(index + 1) % len(choices)]
        self._locate(None)
        self.flash(self.machine_scope_label())

    t.Board.column_items = column_items
    t.Board.machine_scope_label = machine_scope_label
    t.Board.cycle_machine = cycle_machine


def jump(board):
    sys.path.insert(0, board)
    import collect as c

    # The CLI is used on purpose: it keeps the machine-specific routing,
    # credentials and saved connection settings in Herdr, not in this helper.
    local = c.run_herdr("api", "snapshot").get("result", {}).get("snapshot", {})
    parts = [(c.LOCAL, local)]
    replies = []
    lock = threading.Lock()

    def fetch(label):
        try:
            snap = c.run_herdr("api", "snapshot", machine=label, timeout=1.5).get("result", {}).get("snapshot", {})
            with lock:
                replies.append((label, snap))
        except Exception:
            pass

    workers = [threading.Thread(target=fetch, args=(str(row["label"]),), daemon=True)
               for row in c.machine_rows() if c._machine_enabled(row) and not c.is_local(row["label"])]
    for worker in workers:
        worker.start()
    deadline = time.monotonic() + 1.5
    for worker in workers:
        worker.join(max(0, deadline - time.monotonic()))
    with lock:
        parts.extend(sorted(replies))
    candidates = []
    for machine, snap in parts:
        candidates.extend((machine, a) for a in snap.get("agents", []) if visible(a))
    for status in ("blocked", "done"):
        pending = [(machine, a) for machine, a in candidates if a.get("agent_status") == status]
        if not pending:
            continue
        cursor_file = c.runtime_dir() / "human-jump.json"
        try:
            cursor = json.loads(cursor_file.read_text())
        except (OSError, ValueError):
            cursor = {}
        current = next((i for i, (m, a) in enumerate(pending)
                        if cursor.get("machine") == m and cursor.get("pane_id") == a["pane_id"]), -1)
        if current == -1:
            current = next((i for i, (m, a) in enumerate(pending) if c.is_local(m) and a.get("focused")), -1)
        machine, agent = pending[(current + 1) % len(pending)]
        c.run_herdr("agent", "focus", agent["pane_id"], machine=machine)
        with c._MEMO_LOCK:
            c._load_seen()
            seq = agent.get("state_change_seq")
            if isinstance(seq, int):
                c._seen.setdefault(machine, {})[agent["pane_id"]] = seq
                c._save_seen(time.time(), force=True)
        atomic_json(cursor_file, {"machine": machine, "pane_id": agent["pane_id"]})
        print(f"herdr-unread: focused {machine}/{agent['pane_id']} ({status})")
        return 0
    print("herdr-unread: no blocked/done non-thread sessions", file=sys.stderr)
    return 1


if __name__ == "__main__":
    if sys.argv[1] == "--extras":
        sys.path.insert(0, sys.argv[2])
        import collect as c
        atomic_json(Path(sys.argv[3]), {"usage": c.usage_summary(), "plan": c.plan_summary()})
    elif sys.argv[1] == "--jump":
        raise SystemExit(jump(sys.argv[2]))
