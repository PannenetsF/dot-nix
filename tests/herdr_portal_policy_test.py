"""Tests against the installed pinned Portal collector, with no live actions."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
import types
from unittest import mock

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("human_portal_policy", REPO / "config/herdr/portal-policy.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)
registry = json.loads((Path.home() / ".config/herdr/plugins.json").read_text())
PORTAL = Path(next(p["plugin_root"] for p in registry if p["plugin_id"] == "herdr-portal"))
sys.path.insert(0, str(PORTAL / "board"))
# Exercise the repository policy, not an older already-patched live module.
c = types.ModuleType("collect")
c.__file__ = str(PORTAL / "board/collect.py")
source = Path(c.__file__).read_text().split("import dot_nix_portal_policy as _dn_policy")[0]
sys.modules["collect"] = c
exec(compile(source, c.__file__, "exec"), c.__dict__)
policy.install(c)


def pane(pid, role="other", status="blocked", **kwargs):
    return dict(pane_id=pid, workspace_id="w1", tab_id="w1:t1", agent="claude",
                agent_status=status, state_change_seq=9, cwd="/ordinary", revision=1,
                tokens={"hp_role": role, "hp_audience": "internal", "hp_group": "~!" + pid}, **kwargs)


def snapshot(panes):
    return {"agents": panes, "panes": panes,
            "workspaces": [{"workspace_id": "w1", "label": "Project"}],
            "tabs": [{"tab_id": "w1:t1", "label": "Session"}]}


class PortalPolicyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = mock.patch.dict(os.environ, {"HERDR_PORTAL_RUNTIME": self.tmp.name,
                                               "HERDR_PORTAL_STATE_DIR": self.tmp.name,
                                               "HERDR_PORTAL_REMOTE": "0"})
        self.env.start()
        self.addCleanup(self.env.stop)
        c._seen = {}
        c._seen_loaded = False

    def test_local_and_remote_only_human_sessions_in_every_column(self):
        parts = []
        for machine in ["Local", "boe-fyq"]:
            rows = [pane("w1:p1", "coordinator"), pane("w1:p2", "other"),
                    pane("w1:p3", "thread"), pane("w1:p4", "thread", "done")]
            child = pane("w1:p5", "guest")
            child["tokens"]["dn_session"] = "thread"
            rows.append(child)
            parts.append({"machine": machine, "snapshot": snapshot(rows)})
        result = c.assemble_snapshot(parts, legacy_data={"project": [{"id": "t-9999", "group": "waiting-on-you"}]})
        self.assertEqual(len(result["items"]), 4)
        self.assertEqual(len({i["uid"] for i in result["items"]}), 4)
        self.assertEqual(result["counts"]["attention"], 4)
        self.assertEqual({i["pane_id"] for i in result["items"]}, {"w1:p1", "w1:p2"})
        for cards in result["columns"].values():
            self.assertTrue(all(i["hp_role"] != "thread" and i["kind"] != "legacy" for i in cards))

    def test_descendant_and_pre_token_thread_fallbacks(self):
        for field, value in [("cwd", "/home/a/.herdr-projects/p/threads/t-0034/sub"),
                             ("foreground_cwd", "/home/a/.herdr/worktrees/repo/hp-p-t-0034-task"),
                             ("name", "hp-p-t-0034")]:
            row = pane("p")
            row[field] = value
            self.assertFalse(policy.visible(row))
        self.assertTrue(policy.visible(pane("p", "other")))

    def test_remote_last_focused_is_not_marked_seen(self):
        row = pane("w1:p1", "coordinator")
        snap = snapshot([row]); snap["focused_pane_id"] = "w1:p1"
        c.update_seen([{"machine": "boe-fyq", "snapshot": snap}])
        self.assertNotIn("boe-fyq", c.seen_map())
        result = c.assemble_snapshot([{"machine": "boe-fyq", "snapshot": snap}])
        self.assertEqual(result["counts"]["attention"], 1)
        c._seen = {"boe-fyq": {"w1:p1": 9}}
        result = c.assemble_snapshot([{"machine": "boe-fyq", "snapshot": snap}])
        self.assertEqual(result["counts"]["attention"], 0)

    def test_seen_store_merges_other_clients_and_preserves_newest_sequence(self):
        file = c._seen_path()
        file.write_text(json.dumps({"boe-fyq": {"w1:p1": 12}}))
        c._seen = {"Local": {"w1:p1": 9}, "boe-fyq": {"w1:p1": 10}}
        c._seen_loaded = True
        c._save_seen(time.time(), force=True)
        self.assertEqual(json.loads(file.read_text()), {
            "Local": {"w1:p1": 9}, "boe-fyq": {"w1:p1": 12}})
        file.write_text(json.dumps({"boe-fyq": {"w1:p2": 15}}))
        self.assertEqual(c.seen_map()["boe-fyq"], {"w1:p1": 12, "w1:p2": 15})

    def test_default_snapshot_cache_uses_fast_ttl(self):
        self.assertEqual(c.collect_or_error.__defaults__, (0.25,))

    def test_cold_collect_does_not_wait_for_usage_or_legacy_or_ssh(self):
        with mock.patch.object(c, "run_herdr", return_value={"result": {"snapshot": snapshot([pane("w1:p1")])}}), \
             mock.patch.object(c, "usage_summary", side_effect=AssertionError("synchronous usage scan")), \
             mock.patch.object(c, "_legacy_for_collect", side_effect=AssertionError("thread scan")), \
             mock.patch.object(policy.subprocess, "Popen") as spawn:
            start = time.monotonic()
            result = c.collect()
            self.assertLess(time.monotonic() - start, 0.25)
            self.assertTrue(result["ok"])
            self.assertLess(result["collection_ms"], 250)
            spawn.assert_called_once()

    def test_unread_routes_remote_by_machine_and_excludes_threads(self):
        local = snapshot([pane("w1:p1", "thread")])
        remote = snapshot([pane("w1:p1", "coordinator"), pane("w1:p2", "thread")])
        calls = []

        def run(*args, machine=None, **kw):
            calls.append((args, machine))
            return {"result": {"snapshot": remote if machine else local}}

        with mock.patch.object(c, "run_herdr", side_effect=run), \
             mock.patch.object(c, "machine_rows", return_value=[{"label": "boe-fyq"}]):
            self.assertEqual(policy.jump(str(PORTAL / "board")), 0)
        self.assertIn((("agent", "focus", "w1:p1"), "boe-fyq"), calls)
        self.assertFalse(any(args[:2] == ("agent", "focus") and machine is None for args, machine in calls))

    def test_portal_focus_routes_same_id_to_remote_and_acknowledges_it(self):
        parts = [{"machine": m, "snapshot": snapshot([pane("w1:p1", "coordinator")])}
                 for m in ["Local", "boe-fyq"]]
        result = c.assemble_snapshot(parts)
        with mock.patch.object(c, "collect", return_value=result), \
             mock.patch.object(c, "collect_or_error", return_value=result), \
             mock.patch.object(c, "run_herdr", return_value={"ok": True}) as run:
            c.focus_target("w1:p1", "boe-fyq")
        run.assert_called_once_with("agent", "focus", "w1:p1", machine="boe-fyq")
        self.assertEqual(c.seen_map()["boe-fyq"]["w1:p1"], 9)
        self.assertNotIn("Local", c.seen_map())

    def test_offline_remote_keeps_last_good_human_cards_and_machine_identity(self):
        now = time.time()
        with mock.patch.object(c, "_remote_states", {"boe-fyq": {
            "snapshot": snapshot([pane("w1:p1", "coordinator"), pane("w1:p2", "thread")]),
            "ok_at": now - 3600, "error": "SSH timeout"}}):
            parts = c.remote_parts(now)
            result = c.assemble_snapshot(parts)
        self.assertTrue(parts[0]["stale"])
        self.assertEqual([(i["machine"], i["pane_id"]) for i in result["items"]], [("boe-fyq", "w1:p1")])


if __name__ == "__main__":
    unittest.main()
