#!/usr/bin/env python3
"""Regression tests for scripts/tmp_lifecycle.py.

Run: python3 -m unittest discover -s plugins/file-lifecycle/tests
Sandboxes go under $FILE_LIFECYCLE_TEST_DIR when set, else the system temp dir.
"""
import fcntl
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

TOOL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "tmp_lifecycle.py")
SID = "11111111-2222-3333-4444-555555555555"
DAY = 86400


def age(path, days):
    t = time.time() - days * DAY
    if os.path.isdir(path) and not os.path.islink(path):
        for d, dirs, files in os.walk(path):
            for n in dirs + files:
                os.utime(os.path.join(d, n), (t, t), follow_symlinks=False)
    os.utime(path, (t, t), follow_symlinks=False)


def lstart(pid):
    out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                         env={"LC_ALL": "C", "TZ": "UTC0", "PATH": "/bin:/usr/bin"}).stdout
    return " ".join(out.split())


class Base(unittest.TestCase):
    top_level = True

    def setUp(self):
        base = os.environ.get("FILE_LIFECYCLE_TEST_DIR")
        if base:
            os.makedirs(base, exist_ok=True)
        # The tool realpath()s its roots, as lsof reports them; on macOS the temp
        # dir is behind a symlink (/var -> /private/var), so compare resolved paths.
        self.box = os.path.realpath(tempfile.mkdtemp(dir=base))
        self.root = os.path.join(self.box, "tmp")
        os.makedirs(self.root)
        self.cfg_path = os.path.join(self.box, "config.json")
        self.write_config()
        self.env = dict(os.environ, FILE_LIFECYCLE_CONFIG=self.cfg_path, FILE_LIFECYCLE_BUSY_STUB="")
        self.env.pop("CLAUDE_ENV_FILE", None)

    def write_config(self, **over):
        cfg = {"tmp_root": self.root, "archive_root": os.path.join(self.box, "archive"),
               "log": os.path.join(self.box, "log.txt"), "sweep_top_level": self.top_level,
               "default_ttl_days": 7, "session_grace_hours": 24, "session_idle_days": 7, "throttle_hours": 6,
               "entries": [{"pattern": "keepme", "policy": "keep"},
                           {"pattern": "logs", "policy": "ttl-contents", "ttl_days": 30},
                           {"pattern": "flag-off", "policy": "ttl", "ttl_days": 1},
                           {"pattern": "typo", "policy": "kep"},
                           {"pattern": "nopolicy"}]}
        cfg.update(over)
        with open(self.cfg_path, "w") as f:
            json.dump(cfg, f)

    def tearDown(self):
        shutil.rmtree(self.box, ignore_errors=True)

    def run_tool(self, *args, stdin="", env=None):
        return subprocess.run([sys.executable, TOOL, *args], input=stdin, capture_output=True, text=True,
                              env=env or self.env, timeout=60)

    def sweep(self, *extra, env=None):
        r = self.run_tool("sweep", "--force", *extra, env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def mk(self, rel, days=0, content="x"):
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)
        if days:
            age(p, days)
        return p

    def seen(self, key, days):
        """Pretend the sweeper first saw this entry `days` ago."""
        p = os.path.join(self.root, ".seen.json")
        data = {}
        if os.path.exists(p):
            with open(p) as f:
                data = json.load(f)
        data[key] = time.time() - days * DAY
        with open(p, "w") as f:
            json.dump(data, f)

    def exists(self, rel):
        return os.path.lexists(os.path.join(self.root, rel))


class SessionHooks(Base):
    def test_start_creates_dir_env_and_context(self):
        envf = os.path.join(self.box, "envfile")
        env = dict(self.env, CLAUDE_ENV_FILE=envf)
        r = self.run_tool("session-start", "--no-sweep", env=env,
                          stdin=json.dumps({"session_id": SID, "source": "startup", "transcript_path": "/x.jsonl"}))
        self.assertEqual(r.returncode, 0, r.stderr)
        sdir = os.path.join(self.root, "s", SID)
        self.assertTrue(os.path.isdir(sdir))
        with open(envf) as f:
            body = f.read()
        self.assertIn(f"export CLAUDE_SESSION_TMP={shlex.quote(sdir)}", body)
        self.assertIn(f"export CLAUDE_SESSION_ID={shlex.quote(SID)}", body)
        self.assertEqual(os.stat(sdir).st_mode & 0o777, 0o700)
        self.assertIn("CLAUDE_SESSION_TMP", r.stdout)
        self.assertIn("archive.py add", r.stdout)
        with open(os.path.join(sdir, ".meta.json")) as f:
            self.assertEqual(json.load(f)["transcript_path"], "/x.jsonl")

    def test_closed_stdout_does_not_fail_the_hook(self):
        rfd, wfd = os.pipe()
        os.close(rfd)
        try:
            p = subprocess.run([sys.executable, TOOL, "session-start", "--no-sweep"], input=json.dumps({"session_id": SID}),
                               stdout=wfd, stderr=subprocess.PIPE, text=True, env=self.env, timeout=60)
        finally:
            os.close(wfd)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertNotIn("BrokenPipe", p.stderr)
        self.assertTrue(self.exists(f"s/{SID}/.meta.json"))

    def test_start_rejects_malformed_session_id(self):
        traversal = os.path.join(os.pardir, os.pardir, "etc")
        r = self.run_tool("session-start", "--no-sweep", stdin=json.dumps({"session_id": traversal}))
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self.exists("s"))
        self.assertEqual(r.stdout, "")

    def test_start_survives_garbage_stdin(self):
        for stdin in ("not json", "[1, 2]"):
            r = self.run_tool("session-start", "--no-sweep", stdin=stdin)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(self.exists("s"))

    def test_start_heals_file_blocking_s(self):
        self.mk("s", content="junk")
        r = self.run_tool("session-start", "--no-sweep", stdin=json.dumps({"session_id": SID}))
        self.assertEqual(r.returncode, 0)
        self.assertTrue(os.path.isdir(os.path.join(self.root, "s", SID)))

    def test_start_keeps_a_working_symlink_at_s(self):
        elsewhere = os.path.join(self.box, "other-volume")
        os.makedirs(elsewhere)
        os.symlink(elsewhere, os.path.join(self.root, "s"))
        r = self.run_tool("session-start", "--no-sweep", stdin=json.dumps({"session_id": SID}))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.islink(os.path.join(self.root, "s")))
        self.assertTrue(os.path.isdir(os.path.join(elsewhere, SID)))

    def test_unwritable_env_file_still_prints_context(self):
        env = dict(self.env, CLAUDE_ENV_FILE=os.path.join(self.box, "no-such-dir", "env"))
        r = self.run_tool("session-start", "--no-sweep", env=env, stdin=json.dumps({"session_id": SID}))
        self.assertEqual(r.returncode, 0)
        self.assertIn("CLAUDE_SESSION_TMP", r.stdout)

    def test_start_with_broken_config_still_creates_session_dir(self):
        with open(self.cfg_path, "w") as f:
            f.write("{broken")
        env = dict(self.env, HOME=self.box)  # the defaults resolve under HOME — keep them in the sandbox
        r = self.run_tool("session-start", env=env, stdin=json.dumps({"session_id": SID}))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("CLAUDE_SESSION_TMP", r.stdout)
        self.assertTrue(os.path.isdir(os.path.join(self.box, ".claude", "tmp", "s", SID)))
        with open(os.path.join(self.box, ".claude", "groundwork", "state", "file-lifecycle.log")) as f:
            self.assertIn("config error, sweep disabled", f.read())

    def test_resume_clears_ended_marker(self):
        self.mk(f"s/{SID}/work.txt")
        self.mk(f"s/{SID}/.ended")
        self.run_tool("session-start", "--no-sweep", stdin=json.dumps({"session_id": SID, "source": "resume"}))
        self.assertFalse(self.exists(f"s/{SID}/.ended"))
        self.assertTrue(self.exists(f"s/{SID}/work.txt"))

    def test_end_removes_empty_session_dir(self):
        self.run_tool("session-start", "--no-sweep", stdin=json.dumps({"session_id": SID}))
        r = self.run_tool("session-end", stdin=json.dumps({"session_id": SID, "reason": "other"}))
        self.assertEqual(r.returncode, 0)
        self.assertFalse(self.exists(f"s/{SID}"))

    def test_end_marks_nonempty_session_dir(self):
        self.mk(f"s/{SID}/work.txt")
        self.run_tool("session-end", stdin=json.dumps({"session_id": SID, "reason": "clear"}))
        with open(os.path.join(self.root, "s", SID, ".ended")) as f:
            self.assertIn("clear", f.read())
        self.assertTrue(self.exists(f"s/{SID}/work.txt"))


class SweepSessions(Base):
    def meta(self, **kw):
        self.mk(f"s/{SID}/.meta.json", content=json.dumps(kw))

    def test_ended_session_deleted_after_grace(self):
        self.mk(f"s/{SID}/work.txt")
        age(self.mk(f"s/{SID}/.ended"), 2)
        self.sweep()
        self.assertFalse(self.exists(f"s/{SID}"))

    def test_ended_session_kept_within_grace(self):
        self.mk(f"s/{SID}/work.txt", days=30)
        self.mk(f"s/{SID}/.ended")
        self.sweep()
        self.assertTrue(self.exists(f"s/{SID}/work.txt"))

    def test_session_with_fresh_transcript_kept(self):
        transcript = os.path.join(self.box, "t.jsonl")
        open(transcript, "w").close()
        self.meta(transcript_path=transcript)
        self.mk(f"s/{SID}/old.txt")
        age(os.path.join(self.root, "s", SID), 30)
        self.sweep()
        self.assertTrue(self.exists(f"s/{SID}/old.txt"))

    def test_idle_session_with_live_claude_process_kept(self):
        self.meta(transcript_path="/nonexistent.jsonl", claude={"pid": os.getpid(), "lstart": lstart(os.getpid())})
        self.mk(f"s/{SID}/old.txt")
        age(os.path.join(self.root, "s", SID), 30)
        self.sweep()
        self.assertTrue(self.exists(f"s/{SID}/old.txt"))

    def test_reused_pid_does_not_keep_session(self):
        self.meta(transcript_path="/nonexistent.jsonl",
                  claude={"pid": os.getpid(), "lstart": "Thu Jan  1 00:00:00 1970"})
        self.mk(f"s/{SID}/old.txt")
        age(os.path.join(self.root, "s", SID), 30)
        self.sweep()
        self.assertFalse(self.exists(f"s/{SID}"))

    def test_orphan_session_deleted(self):
        self.meta(transcript_path="/nonexistent.jsonl")
        self.mk(f"s/{SID}/old.txt")
        age(os.path.join(self.root, "s", SID), 8)
        self.sweep()
        self.assertFalse(self.exists(f"s/{SID}"))

    def test_busy_session_kept(self):
        self.mk(f"s/{SID}/work.txt")
        age(self.mk(f"s/{SID}/.ended"), 2)
        env = dict(self.env, FILE_LIFECYCLE_BUSY_STUB=os.path.join(self.root, "s", SID, "work.txt"))
        self.sweep(env=env)
        self.assertTrue(self.exists(f"s/{SID}/work.txt"))

    def test_non_session_dir_under_s_is_left_alone(self):
        for name in ("my-notes", "22222222-3333-4444-5555-666666666666"):
            self.mk(f"s/{name}/keep.txt")
            age(os.path.join(self.root, "s", name), 400)
        r = self.sweep("--verbose")
        self.assertTrue(self.exists("s/my-notes/keep.txt"))
        self.assertTrue(self.exists("s/22222222-3333-4444-5555-666666666666/keep.txt"))
        self.assertIn("SKIP(not a session dir) s/my-notes", r.stdout)

    def test_malformed_meta_does_not_stop_other_sessions(self):
        self.mk("s/00000000-bad-meta/.meta.json", content="[1, 2]")
        age(os.path.join(self.root, "s", "00000000-bad-meta"), 30)
        self.mk("s/00000000-bad-claude/.meta.json", content=json.dumps({"claude": "x", "transcript_path": 5}))
        age(os.path.join(self.root, "s", "00000000-bad-claude"), 30)
        self.mk(f"s/{SID}/work.txt")
        age(self.mk(f"s/{SID}/.ended"), 2)
        self.sweep()
        self.assertFalse(self.exists(f"s/{SID}"))
        self.assertFalse(self.exists("s/00000000-bad-meta"))
        self.assertFalse(self.exists("s/00000000-bad-claude"))

    def test_git_inside_session_dir_kept(self):
        self.mk(f"s/{SID}/clone/.git/HEAD", content="ref: refs/heads/main")
        age(self.mk(f"s/{SID}/.ended"), 2)
        r = self.sweep("--verbose")
        self.assertTrue(self.exists(f"s/{SID}/clone/.git/HEAD"))
        self.assertIn("KEEP(contains git", r.stdout)


class TopLevelOff(Base):
    top_level = False

    def test_default_off_leaves_top_level_alone(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        self.mk(f"s/{SID}/work.txt")
        age(self.mk(f"s/{SID}/.ended"), 2)
        self.sweep()
        self.assertTrue(os.path.exists(p))
        self.assertFalse(self.exists(f"s/{SID}"))
        self.assertIn("top-level sweep is off", self.run_tool("status").stdout)

    def test_missing_config_defaults_to_off(self):
        home_tmp = os.path.join(self.box, ".claude", "tmp")
        os.makedirs(home_tmp)
        p = os.path.join(home_tmp, "old.txt")
        with open(p, "w") as f:
            f.write("x")
        age(p, 30)
        with open(os.path.join(home_tmp, ".seen.json"), "w") as f:
            json.dump({"old.txt": time.time() - 30 * DAY}, f)
        env = dict(self.env, HOME=self.box, FILE_LIFECYCLE_CONFIG=os.path.join(self.box, "absent.json"))
        self.sweep(env=env)
        self.assertTrue(os.path.exists(p))


class SweepTopLevel(Base):
    def test_unregistered_old_entry_deleted_young_kept(self):
        self.mk("old-report.html", days=8)
        self.mk("new-report.html", days=6)
        self.seen("old-report.html", 8)
        self.seen("new-report.html", 8)
        self.sweep()
        self.assertFalse(self.exists("old-report.html"))
        self.assertTrue(self.exists("new-report.html"))

    def test_moved_in_file_with_old_mtime_waits_for_ttl(self):
        self.mk("moved-in.html", days=300)
        self.sweep()
        self.assertTrue(self.exists("moved-in.html"))
        self.seen("moved-in.html", 8)
        self.sweep()
        self.assertFalse(self.exists("moved-in.html"))

    def test_seen_ledger_forgets_vanished_entries(self):
        self.seen("gone.txt", 30)
        self.mk("here.txt")
        self.sweep()
        with open(os.path.join(self.root, ".seen.json")) as f:
            ledger = json.load(f)
        self.assertNotIn("gone.txt", ledger)
        self.assertIn("here.txt", ledger)

    def test_dir_age_uses_newest_file(self):
        self.mk("work/a.txt", days=30)
        self.mk("work/b.txt", days=1)
        age(os.path.join(self.root, "work"), 30)
        os.utime(os.path.join(self.root, "work", "b.txt"))
        self.seen("work", 30)
        self.sweep()
        self.assertTrue(self.exists("work/a.txt"))

    def test_keep_policy_never_deleted(self):
        self.mk("keepme", days=400)
        self.seen("keepme", 400)
        self.sweep()
        self.assertTrue(self.exists("keepme"))

    def test_unknown_or_missing_policy_keeps(self):
        for name in ("typo", "nopolicy"):
            self.mk(name, days=400)
            self.seen(name, 400)
        self.sweep()
        self.assertTrue(self.exists("typo"))
        self.assertTrue(self.exists("nopolicy"))

    def test_ttl_contents_prunes_children_keeps_dir(self):
        self.mk("logs/old.log", days=31)
        self.mk("logs/new.log", days=2)
        old = time.time() - 400 * DAY
        os.utime(os.path.join(self.root, "logs"), (old, old))
        self.seen("logs/old.log", 31)
        self.seen("logs/new.log", 31)
        self.sweep()
        self.assertTrue(os.path.isdir(os.path.join(self.root, "logs")))
        self.assertFalse(self.exists("logs/old.log"))
        self.assertTrue(self.exists("logs/new.log"))

    def test_registered_short_ttl(self):
        self.mk("flag-off", days=2)
        self.seen("flag-off", 2)
        self.sweep()
        self.assertFalse(self.exists("flag-off"))

    def test_git_worktree_kept_even_when_old(self):
        self.mk("wt/.git", content="gitdir: /somewhere")
        self.mk("wt/scenario.py")
        age(os.path.join(self.root, "wt"), 30)
        self.seen("wt", 30)
        r = self.sweep("--verbose")
        self.assertTrue(self.exists("wt/scenario.py"))
        self.assertIn("KEEP(contains git", r.stdout)

    def test_git_inside_ttl_contents_kept(self):
        self.mk("logs/wt/.git/HEAD", content="ref: refs/heads/main")
        self.mk("logs/wt/work.py")
        age(os.path.join(self.root, "logs", "wt"), 40)
        self.seen("logs/wt", 40)
        self.sweep()
        self.assertTrue(self.exists("logs/wt/work.py"))

    def test_bare_repo_kept(self):
        self.mk("mirror.git/HEAD", content="ref: refs/heads/main")
        self.mk("mirror.git/objects/ab/cdef")
        self.mk("mirror.git/refs/heads/main")
        age(os.path.join(self.root, "mirror.git"), 30)
        self.seen("mirror.git", 30)
        self.sweep()
        self.assertTrue(self.exists("mirror.git/HEAD"))

    def test_busy_entry_kept(self):
        p = self.mk("running.log", days=30)
        self.seen("running.log", 30)
        self.sweep(env=dict(self.env, FILE_LIFECYCLE_BUSY_STUB=p))
        self.assertTrue(os.path.exists(p))

    def test_lsof_failure_deletes_nothing(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        self.mk(f"s/{SID}/work.txt")
        age(self.mk(f"s/{SID}/.ended"), 2)
        self.sweep(env=dict(self.env, FILE_LIFECYCLE_BUSY_STUB="FAIL"))
        self.assertTrue(os.path.exists(p))
        self.assertTrue(self.exists(f"s/{SID}/work.txt"))

    def test_broken_config_deletes_nothing(self):
        # Sweeping with the defaults instead would drop an ended session under HOME's tmp root.
        sdir = os.path.join(self.box, ".claude", "tmp", "s", SID)
        os.makedirs(sdir)
        with open(os.path.join(sdir, "work.txt"), "w") as f:
            f.write("x")
        ended = os.path.join(sdir, ".ended")
        open(ended, "w").close()
        age(ended, 2)
        with open(self.cfg_path, "w") as f:
            f.write('{"entries": "not-a-list"}')
        env = dict(self.env, HOME=self.box)
        r = self.run_tool("sweep", "--force", env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(os.path.exists(os.path.join(sdir, "work.txt")))
        self.assertIn("config error", self.run_tool("status", env=env).stdout)

    def test_wrong_typed_or_unsafe_config_deletes_nothing(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        bad = [{"sweep_top_level": "false"}, {"default_ttl_days": 0}, {"throttle_hours": "6"},
               {"entries": [{"pattern": "old.txt", "policy": "ttl", "ttl_days": "1"}]},
               {"tmp_root": ""}, {"tmp_root": "relative/tmp"}, {"tmp_root": "~"}, {"tmp_root": "/"},
               {"tmp_root": self.box}, {"log": 5}]
        os.makedirs(os.path.join(self.box, ".git"))  # makes the sandbox itself look like a checkout
        for over in bad:
            self.write_config(**over)
            env = dict(self.env, HOME=self.box)
            r = self.run_tool("sweep", "--force", env=env)
            self.assertEqual(r.returncode, 0, f"{over}: {r.stderr}")
            self.assertTrue(os.path.exists(p), over)
            self.assertIn("config error", self.run_tool("status", env=env).stdout, over)
            r = self.run_tool("session-start", "--no-sweep", env=env, stdin=json.dumps({"session_id": SID}))
            self.assertEqual(r.returncode, 0, f"{over}: {r.stderr}")
            self.assertNotIn("Traceback", r.stderr)

    def test_missing_or_silent_lsof_deletes_nothing(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        silent = os.path.join(self.box, "fake-lsof")
        with open(silent, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(silent, 0o755)
        for lsof in ("", os.path.join(self.box, "no-such-lsof"), silent):
            env = dict(self.env, FILE_LIFECYCLE_LSOF=lsof)
            env.pop("FILE_LIFECYCLE_BUSY_STUB")
            self.sweep(env=env)
            self.assertTrue(os.path.exists(p), lsof)

    def test_symlinked_s_and_ttl_contents_never_reach_outside(self):
        outside = os.path.join(self.box, "outside")
        os.makedirs(os.path.join(outside, "11111111-aaaa"))
        for rel in ("11111111-aaaa/.ended", "11111111-aaaa/work.txt", "old.log"):
            with open(os.path.join(outside, rel), "w") as f:
                f.write("keep")
        age(outside, 400)
        os.symlink(outside, os.path.join(self.root, "s"))
        os.symlink(outside, os.path.join(self.root, "logs"))
        self.seen("logs/old.log", 400)
        self.seen("logs/11111111-aaaa", 400)
        self.sweep()
        self.assertTrue(os.path.exists(os.path.join(outside, "11111111-aaaa", "work.txt")))
        self.assertTrue(os.path.exists(os.path.join(outside, "old.log")))

    def test_symlink_removed_without_touching_target(self):
        outside = os.path.join(self.box, "outside")
        os.makedirs(outside)
        with open(os.path.join(outside, "precious.txt"), "w") as f:
            f.write("keep")
        link = os.path.join(self.root, "link")
        os.symlink(outside, link)
        age(link, 30)
        self.seen("link", 30)
        self.sweep()
        self.assertFalse(os.path.lexists(link))
        self.assertTrue(os.path.exists(os.path.join(outside, "precious.txt")))

    def test_dry_run_deletes_nothing(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        r = self.run_tool("sweep", "--dry-run")
        self.assertIn("WOULD-DELETE old.txt", r.stdout)
        self.assertTrue(os.path.exists(p))

    def test_throttle_skips_second_run(self):
        self.run_tool("sweep")
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        self.run_tool("sweep")
        self.assertTrue(os.path.exists(p))
        self.sweep()
        self.assertFalse(os.path.exists(p))

    def test_same_name_recreated_is_a_new_item(self):
        self.mk("foo", days=30)
        self.sweep()  # records the inode in the ledger
        with open(os.path.join(self.root, ".seen.json")) as f:
            ledger = json.load(f)
        ledger["foo"][0] -= 30 * DAY
        with open(os.path.join(self.root, ".seen.json"), "w") as f:
            json.dump(ledger, f)
        os.unlink(os.path.join(self.root, "foo"))
        self.mk("other", content="keeps inode numbers apart")
        self.mk("foo", days=30)  # comes back with an old mtime, like tar -x
        self.sweep()
        self.assertTrue(self.exists("foo"))

    def test_busy_item_keeps_first_seen(self):
        p = self.mk("running.log", days=30)
        self.seen("running.log", 30)
        self.sweep(env=dict(self.env, FILE_LIFECYCLE_BUSY_STUB=p))
        self.sweep()
        self.assertFalse(os.path.exists(p))

    def test_malformed_ledger_does_not_stop_cleanup(self):
        p = self.mk("old.txt", days=30)
        with open(os.path.join(self.root, ".seen.json"), "w") as f:
            f.write("[]")
        self.sweep()
        self.assertTrue(os.path.exists(p))  # a new ledger starts, so it survives this round
        with open(os.path.join(self.root, ".seen.json")) as f:
            self.assertIn("old.txt", json.load(f))

    def test_status_reports_when_locked(self):
        with open(os.path.join(self.root, ".sweep.lock"), "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            r = self.run_tool("status")
        self.assertIn("another sweep is running", r.stdout)

    def test_concurrent_sweep_skips_when_locked(self):
        p = self.mk("old.txt", days=30)
        self.seen("old.txt", 30)
        with open(os.path.join(self.root, ".sweep.lock"), "w") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            self.sweep()
            self.assertTrue(os.path.exists(p))
        self.sweep()
        self.assertFalse(os.path.exists(p))

    def test_dotfiles_and_missing_root(self):
        p = self.mk(".internal", days=30)
        self.sweep()
        self.assertTrue(os.path.exists(p))
        self.write_config(tmp_root=os.path.join(self.box, "nope"))
        r = self.run_tool("sweep", "--force")
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
