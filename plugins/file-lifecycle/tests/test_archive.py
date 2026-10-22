#!/usr/bin/env python3
"""Regression tests for scripts/archive.py.

Run: python3 -m unittest discover -s plugins/file-lifecycle/tests
Credential-shaped test values are assembled at run time so no secret-looking literal ships in this file.
"""
import bz2
import datetime
import gzip
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
import zipfile

TOOL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "archive.py")
TODAY = datetime.date.today().isoformat()
PW = "hunter2" * 2
JWT = "eyJ" + "hbGciOiJIUzI1NiJ9" + "." + "eyJ" + "zdWIiOiIxMjM0NTY3ODkwIn0" + ".sig"
AWS_ID = "AK" + "IA" + "IOSFODNN7EXAMPLE"


class ArchiveTest(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("FILE_LIFECYCLE_TEST_DIR")
        if base:
            os.makedirs(base, exist_ok=True)
        self.box = tempfile.mkdtemp(dir=base)
        self.root = os.path.join(self.box, "archive")
        self.src = os.path.join(self.box, "src")
        os.makedirs(self.src)
        cfg = os.path.join(self.box, "config.json")
        with open(cfg, "w") as f:
            json.dump({"archive_root": self.root}, f)
        self.env = dict(os.environ, FILE_LIFECYCLE_CONFIG=cfg, CLAUDE_SESSION_ID="sess-1")

    def tearDown(self):
        shutil.rmtree(self.box, ignore_errors=True)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True, env=self.env, timeout=60)

    def mk(self, name, content="hello"):
        p = os.path.join(self.src, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)
        return p

    def mkb(self, name, data):
        p = os.path.join(self.src, name)
        with open(p, "wb") as f:
            f.write(data)
        return p

    def add(self, path, *extra, cat="reports", topic="weekly report", why="evidence for the monthly review"):
        return self.run_tool("add", path, "--cat", cat, "--topic", topic, "--why", why, *extra)

    def index(self):
        with open(os.path.join(self.root, "index.jsonl")) as f:
            return [json.loads(line) for line in f]

    def test_add_moves_with_dated_name_and_indexes(self):
        p = self.mk("report.html")
        r = self.add(p, "--slug", "token-usage", "--ticket", "PROJ-1", "--review", "2099-01-01")
        self.assertEqual(r.returncode, 0, r.stderr)
        rel = f"reports/{TODAY}_token-usage.html"
        self.assertFalse(os.path.exists(p))
        self.assertTrue(os.path.exists(os.path.join(self.root, rel)))
        row = self.index()[0]
        self.assertEqual((row["path"], row["ticket"], row["session"], row["review_by"]),
                         (rel, "PROJ-1", "sess-1", "2099-01-01"))
        with open(os.path.join(self.root, "INDEX.md")) as f:
            md = f.read()
        self.assertIn(f"`{rel}`", md)
        self.assertIn("evidence for the monthly review", md)

    def test_unicode_slug_kept(self):
        p = self.mk("주간 리포트.md")
        self.assertEqual(self.add(p, cat="notes").returncode, 0)
        self.assertEqual(self.index()[0]["path"], f"notes/{TODAY}_주간-리포트.md")

    def test_copy_keeps_source(self):
        p = self.mk("a.md")
        self.assertEqual(self.add(p, "--copy").returncode, 0)
        self.assertTrue(os.path.exists(p))

    def test_secret_content_refused_and_source_untouched(self):
        p = self.mk("notes.md", f"url=postgresql://h/db?user=q&password={PW}")
        r = self.add(p)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("password-assignment", r.stderr)
        self.assertNotIn(PW, r.stderr)
        self.assertTrue(os.path.exists(p))
        self.assertFalse(os.path.exists(os.path.join(self.root, "index.jsonl")))

    def test_secret_in_nested_dir_and_name_refused(self):
        self.mk("bundle/ok.md")
        self.mk("bundle/sub/api-token-prod", "x")
        r = self.add(os.path.join(self.src, "bundle"), cat="backups")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("secret-like-filename", r.stderr)

    def test_otp_and_jdbc_names_refused_ordinary_words_pass(self):
        for name in ("jumphost-otp.txt", "totp_seed", "db-jdbc.properties", "mfa.txt"):
            r = self.add(self.mk(name, "plain"), cat="notes")
            self.assertIn("secret-like-filename", r.stderr, name)
        for i, name in enumerate(("footprint.md", "hotplate-notes.md")):
            r = self.add(self.mk(name, f"plain {i}"), cat="notes")
            self.assertEqual(r.returncode, 0, f"{name}: {r.stderr}")

    def test_jwt_refused(self):
        p = self.mk("log.txt", f"auth {JWT}")
        self.assertIn("jwt", self.add(p).stderr)

    def test_secret_inside_tarball_and_zip_refused(self):
        inner = self.mk("pack/conf.py", "API_KEY = '" + "abcdefghijkl" + "1234'")
        tgz = os.path.join(self.src, "bundle.tgz")
        with tarfile.open(tgz, "w:gz") as tf:
            tf.add(inner, arcname="conf.py")
        r = self.add(tgz, cat="backups")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("bundle.tgz!conf.py", r.stderr)
        zp = os.path.join(self.src, "bundle.zip")
        with zipfile.ZipFile(zp, "w") as zf:
            zf.writestr("x/.env", "A=1")
        self.assertIn("secret-like-filename", self.add(zp, cat="backups").stderr)
        clean = os.path.join(self.src, "clean.tgz")
        ok = self.mk("pack2/readme.md", "nothing here")
        with tarfile.open(clean, "w:gz") as tf:
            tf.add(ok, arcname="readme.md")
        self.assertEqual(self.add(clean, cat="backups").returncode, 0)

    def test_bypass_shapes_all_refused(self):
        """Shapes that slipped past earlier versions of the scanner. Every value is fake."""
        cases = {
            "a.json": ('{"password": "' + PW + '"}').encode(),
            "b.ini": b"aws_secret_access_key = " + b"A" * 40,
            "c.env.txt": b"AWS_SECRET_ACCESS_KEY=" + b"B" * 40,
            "h.txt": ("db postgres://user:" + PW + "@host:5432/db").encode(),
            "h2.txt": ("Authorization: " + "Bearer " + "abcdefghijklmnopqrstuvwxyz012345").encode(),
            "g.txt": ("password=" + PW).encode("utf-16"),
            "f.txt.gz": gzip.compress(("password=" + PW).encode()),
            "f2.txt.bz2": bz2.compress(("password=" + PW).encode()),
        }
        zbuf = io.BytesIO()
        with zipfile.ZipFile(zbuf, "w") as zf:
            zf.writestr("conf.yaml", "password: " + PW)
        tbuf = io.BytesIO()
        with tarfile.open(fileobj=tbuf, mode="w:gz") as tf:
            info = tarfile.TarInfo("inner.zip")
            info.size = len(zbuf.getvalue())
            tf.addfile(info, io.BytesIO(zbuf.getvalue()))
        cases["i.tgz"] = tbuf.getvalue()
        for name, data in cases.items():
            p = self.mkb(name, data)
            r = self.add(p, cat="notes")
            self.assertNotEqual(r.returncode, 0, f"{name} got through")
            self.assertTrue(os.path.exists(p), name)
            self.assertNotIn("hunter2", r.stderr)
            # Refused as an unscannable binary is not the same as found by unpacking — compressed and
            # UTF-16 content must be caught by the content patterns.
            self.assertNotIn("unscannable-binary", r.stderr, name)

    def test_unscannable_refused_unless_allowed(self):
        big = self.mk("big.log", "a" * (5 * 1024 * 1024 + 10))
        r = self.add(big, cat="data")
        self.assertIn("too-large-to-scan", r.stderr)
        self.assertIn("--allow-unscanned", r.stderr)
        blob = self.mkb("blob.bin", b"\0\1\2binary")
        self.assertIn("unscannable-binary", self.add(blob, cat="data").stderr)
        self.assertEqual(self.add(blob, "--allow-unscanned", cat="data").returncode, 0)
        png = self.mkb("shot.png", b"\x89PNG\r\n\x1a\n\0\0")
        self.assertEqual(self.add(png, cat="reports").returncode, 0)

    def test_allow_unscanned_does_not_allow_pattern_hits(self):
        p = self.mk("x.yaml", "password: " + PW)
        self.assertNotEqual(self.add(p, "--allow-unscanned").returncode, 0)

    def test_symlink_source_is_scanned_at_target(self):
        self.mk("secretdir/app.yaml", "password: " + PW)
        link = os.path.join(self.src, "link")
        os.symlink(os.path.join(self.src, "secretdir"), link)
        r = self.add(link, "--copy", cat="notes")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("password-assignment", r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.root, "index.jsonl")))

    def test_hash_has_boundaries(self):
        self.mk("d1/a", "bc")
        self.mk("d2/ab", "c")
        self.assertEqual(self.add(os.path.join(self.src, "d1"), cat="data").returncode, 0)
        self.assertEqual(self.add(os.path.join(self.src, "d2"), cat="data").returncode, 0)

    def test_duplicate_within_one_call_refused(self):
        a = self.mk("a.txt", "same")
        b = self.mk("b.txt", "same")
        r = self.run_tool("add", a, b, "--cat", "reports", "--topic", "t", "--why", "w")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("already archived", r.stderr)
        self.assertTrue(os.path.exists(a) and os.path.exists(b))

    def test_corrupt_index_blocks_writes(self):
        self.add(self.mk("a.html"))
        with open(os.path.join(self.root, "index.jsonl"), "a") as f:
            f.write("{broken\n")
        r = self.add(self.mk("b.html", "other"))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("corrupt", r.stderr)
        self.assertEqual(self.run_tool("find", "weekly").returncode, 0)

    def test_broken_config_refuses(self):
        with open(self.env["FILE_LIFECYCLE_CONFIG"], "w") as f:
            f.write("{broken")
        self.env["HOME"] = self.box  # falling back to the defaults would write under HOME
        r = self.add(self.mk("a.html"))
        self.assertFalse(os.path.exists(os.path.join(self.box, "claude-archive")))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("config error", r.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.src, "a.html")))

    def test_symlink_not_moved(self):
        target = self.mk("repo/README.md", "plain readme")
        link = os.path.join(self.src, "report-link.md")
        os.symlink(target, link)
        r = self.add(link, cat="notes")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--copy", r.stderr)
        self.assertTrue(os.path.exists(target))
        self.assertEqual(self.add(link, "--copy", cat="notes").returncode, 0)
        self.assertTrue(os.path.exists(target))

    def test_encrypted_zip_is_unreadable_not_crash(self):
        zipbin = shutil.which("zip")
        if not zipbin:
            self.skipTest("zip CLI not installed")
        plain = self.mk("enc/in.txt", "hello")
        zp = os.path.join(self.src, "enc.zip")
        subprocess.run([zipbin, "-q", "-j", "-P", "pw", zp, plain], check=True)
        r = self.add(zp, cat="backups")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("unreadable-archive", r.stderr)
        self.assertNotIn("Traceback", r.stderr)
        self.assertEqual(self.add(zp, "--allow-unscanned", cat="backups").returncode, 0)

    def test_ordinary_code_is_not_a_secret(self):
        p = self.mk("tool.py", "\n".join([
            "if token:", "    return None",
            "token = get_token()", "token = parts[0]",
            'password = os.environ["DB_PASSWORD"]',
            '"password": "<YOUR_PASSWORD>"',
            "secret: never print the value",
            "- token: ok",
        ]))
        r = self.add(p, cat="scripts")
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_accept_hit_overrides_one_reviewed_path(self):
        self.mk("pack/example.md", "password: examplepassword")
        self.mk("pack/real.md", "password: " + PW)
        d = os.path.join(self.src, "pack")
        r = self.add(d, "--accept-hit", "example.md", cat="notes")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("real.md", r.stderr)
        self.assertNotIn("example.md", r.stderr)
        r = self.add(d, "--accept-hit", "example.md", "--accept-hit", "real.md", cat="notes")
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_macos_and_office_members_pass(self):
        tgz = os.path.join(self.src, "mac.tgz")
        with tarfile.open(tgz, "w:gz") as tf:
            for name, data in (("._notes.md", b"\x00\x05\x16\x07" + b"\0" * 40), ("notes.md", b"hello")):
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        self.assertEqual(self.add(tgz, cat="backups").returncode, 0)
        xl = os.path.join(self.src, "sheet.xlsx")
        with zipfile.ZipFile(xl, "w") as zf:
            zf.writestr("xl/workbook.xml", "<workbook/>")
            zf.writestr("xl/printerSettings/printerSettings1.bin", b"\0\1\2")
        self.assertEqual(self.add(xl, cat="data").returncode, 0)

    def test_media_with_embedded_key_refused(self):
        png = self.mkb("shot.png", b"\x89PNG\r\n\x1a\n\0\0tEXt " + AWS_ID.encode())
        self.assertIn("aws-access-key", self.add(png, cat="reports").stderr)

    def test_total_budget_limits_archive_bombs(self):
        zp = os.path.join(self.src, "bomb.zip")
        with zipfile.ZipFile(zp, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for i in range(12):
                zf.writestr(f"m{i}.txt", "a" * (5 * 1024 * 1024 - 100))
        self.assertIn("too-large-to-scan", self.add(zp, cat="data").stderr)

    def test_url_pattern_is_not_quadratic(self):
        p = self.mk("hex.txt", "a" * 80000)
        t0 = time.time()
        self.assertEqual(self.add(p, cat="data").returncode, 0)
        self.assertLess(time.time() - t0, 3)

    def test_same_filename_twice_keeps_extension(self):
        a = self.mk("x/notes.md", "one")
        b = self.mk("y/notes.md", "two")
        r = self.run_tool("add", a, b, "--cat", "notes", "--topic", "t", "--why", "w")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(sorted(x["path"] for x in self.index()),
                         [f"notes/{TODAY}_notes-2.md", f"notes/{TODAY}_notes.md"])

    def test_symlinked_subdir_counts_in_hash(self):
        for d, tgt in (("t1", "A"), ("t2", "B")):
            self.mk(f"{d}/f.txt", "same")
            os.makedirs(os.path.join(self.src, tgt), exist_ok=True)
            os.symlink(os.path.join(self.src, tgt), os.path.join(self.src, d, "link"))
        self.assertEqual(self.add(os.path.join(self.src, "t1"), cat="data").returncode, 0)
        self.assertEqual(self.add(os.path.join(self.src, "t2"), cat="data").returncode, 0)

    def test_duplicate_content_refused(self):
        a = self.mk("a.html", "same")
        b = self.mk("b.html", "same")
        self.assertEqual(self.add(a).returncode, 0)
        r = self.add(b)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("already archived", r.stderr)
        self.assertTrue(os.path.exists(b))

    def test_directory_add_and_name_collision(self):
        self.mk("dir1/x.txt", "1")
        self.mk("dir2/x.txt", "2")
        self.assertEqual(self.add(os.path.join(self.src, "dir1"), "--slug", "pack", cat="data").returncode, 0)
        self.assertEqual(self.add(os.path.join(self.src, "dir2"), "--slug", "pack", cat="data").returncode, 0)
        paths = sorted(r["path"] for r in self.index())
        self.assertEqual(paths, [f"data/{TODAY}_pack", f"data/{TODAY}_pack-2"])
        self.assertEqual([r["kind"] for r in self.index()], ["dir", "dir"])

    def test_check_reports_drift(self):
        self.add(self.mk("a.html"))
        self.assertEqual(self.run_tool("check").returncode, 0)
        rel = self.index()[0]["path"]
        os.unlink(os.path.join(self.root, rel))
        with open(os.path.join(self.root, "reports", "stray.txt"), "w") as f:
            f.write("s")
        r = self.run_tool("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("missing file", r.stdout)
        self.assertIn("not in index: reports/stray.txt", r.stdout)

    def test_check_flags_overdue_review(self):
        self.add(self.mk("a.html"), "--review", "2000-01-01")
        r = self.run_tool("check")
        self.assertEqual(r.returncode, 1)
        self.assertIn("review overdue", r.stdout)

    def test_remove_requires_yes_and_stays_inside(self):
        self.add(self.mk("a.html"))
        rel = self.index()[0]["path"]
        self.assertNotEqual(self.run_tool("remove", rel).returncode, 0)
        self.assertTrue(os.path.exists(os.path.join(self.root, rel)))
        self.assertNotEqual(self.run_tool("remove", os.path.join(os.pardir, "src"), "--yes").returncode, 0)
        self.assertTrue(os.path.isdir(self.src))
        self.assertEqual(self.run_tool("remove", rel, "--yes").returncode, 0)
        self.assertEqual(self.index(), [])

    def test_find_and_pipe_escaping(self):
        self.add(self.mk("a.html"), topic="A | B comparison", why="reuse")
        self.assertIn("A | B comparison", self.run_tool("find", "comparison").stdout)
        self.assertIn("no match", self.run_tool("find", "nothing-like-this").stdout)
        with open(os.path.join(self.root, "INDEX.md")) as f:
            self.assertIn("A \\| B comparison", f.read())

    def test_invalid_args(self):
        p = self.mk("a.html")
        self.assertNotEqual(self.run_tool("add", p, "--cat", "nope", "--topic", "t", "--why", "w").returncode, 0)
        self.assertNotEqual(self.add(p, "--review", "2026-13-40").returncode, 0)
        self.assertNotEqual(self.add(os.path.join(self.src, "missing")).returncode, 0)
        self.assertTrue(os.path.exists(p))


if __name__ == "__main__":
    unittest.main(verbosity=1)
