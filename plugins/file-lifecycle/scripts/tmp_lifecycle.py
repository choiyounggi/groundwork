#!/usr/bin/env python3
"""Lifecycle for Claude Code scratch files — a per-session temp dir plus an age-based sweeper.

Layout (after XDG_RUNTIME_DIR: lifetime bound to the session; and systemd tmpfiles.d: age-based
cleanup with an exclusion list):
  <tmp_root>/s/<session_id>/   per-session scratch dir, exposed as $CLAUDE_SESSION_TMP
  <tmp_root>/<other>           fixed paths that tools write to. Swept only when `sweep_top_level`
                               is on: registered entries follow their policy, unregistered ones are
                               deleted once both their last change and their first sighting are
                               older than default_ttl_days.

Commands (hooks pass the hook JSON on stdin):
  session-start   create the session dir, write the env vars to CLAUDE_ENV_FILE, print one context
                  line, start the sweeper in the background
  session-end     leave an .ended marker (an empty dir is removed at once). Deletion waits for the
                  grace period: the SessionEnd hook has a short time budget that a large tree can
                  outrun, and a /clear or resume may need the files again.
  sweep [--dry-run] [--force] [--verbose]   apply the rules (without --force, skipped inside the
                  throttle window)
  status          what a sweep would delete now (dry run)

Judging age by mtime alone deletes a file that arrived with an old mtime (mv, tar -x) on the next
sweep. So the sweeper records when it first saw each entry in .seen.json and deletes only when the
last change and the first sighting are both past the TTL — the tmpfiles.d rule that any recent
timestamp keeps an entry. ctime is not used because tests cannot set it.

Safety: never touches paths outside the root or symlink targets; skips entries a process holds open
or uses as cwd; deletes nothing when lsof fails or is missing; keeps (and reports) entries that
contain a git repository; keeps a session dir while the claude process that opened it is alive;
deletes nothing when the config file exists but cannot be parsed.
"""
import argparse
import fcntl
import fnmatch
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

from lifecycle_config import HOME, POLICIES, expand, load_config

SID_RE = re.compile(r"^[A-Za-z0-9_-]{8,128}$")
DAY = 86400
HERE = os.path.dirname(os.path.abspath(__file__))
PS_ENV = {"LC_ALL": "C", "TZ": "UTC0", "PATH": "/bin:/usr/bin"}


def tilde(path):
    return "~" + path[len(HOME):] if HOME != os.sep and (path == HOME or path.startswith(HOME + os.sep)) else path


def log(cfg, msg):
    p = expand(cfg["log"])
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + msg + "\n")
        with open(p, encoding="utf-8") as f:
            lines = f.readlines()
        if len(lines) > 2000:
            with open(p, "w", encoding="utf-8") as f:
                f.writelines(lines[-1000:])
    except OSError:
        pass


def read_hook_input():
    try:
        data = sys.stdin.read()
        parsed = json.loads(data) if data.strip() else {}
        return parsed if isinstance(parsed, dict) else {}
    except (ValueError, OSError):
        return {}


def session_dir(cfg, sid):
    if not SID_RE.match(sid or ""):
        return None
    return os.path.join(expand(cfg["tmp_root"]), "s", sid)


def ps_info(pid):
    """(ppid, start time, comm). The start time fingerprints the process against PID reuse; locale and
    timezone are pinned so every session renders the same string."""
    try:
        out = subprocess.run(["ps", "-o", "ppid=,lstart=,comm=", "-p", str(pid)], capture_output=True,
                             text=True, timeout=5, env=PS_ENV).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return None
    if len(out) < 7:
        return None
    return int(out[0]), " ".join(out[1:6]), " ".join(out[6:])


def proc_start(pid):
    info = ps_info(pid)
    return info[1] if info else None


def claude_ancestor():
    """The claude process (pid, start time) that launched this hook: claude -> sh -> python."""
    pid = os.getppid()
    for _ in range(6):
        info = ps_info(pid)
        if not info:
            return None
        ppid, started, comm = info
        if os.path.basename(comm) == "claude":
            return {"pid": pid, "lstart": started}
        if ppid <= 1:
            return None
        pid = ppid
    return None


def say(text):
    try:
        print(text)
        sys.stdout.flush()
    except BrokenPipeError:  # the hook runner stopped reading; the context line is optional
        # Point stdout at devnull, or Python flushes it again at exit and the hook fails with code 120.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


def cmd_session_start(args):
    cfg, err = load_config()
    if err:
        log(cfg, f"config error, sweep disabled: {err}")
    data = read_hook_input()
    sid = data.get("session_id", "")
    d = session_dir(cfg, sid)
    if not d:
        return 0
    sroot = os.path.dirname(d)
    if os.path.lexists(sroot) and not os.path.isdir(sroot):
        os.unlink(sroot)  # a stray file or dangling link at s/ would make every session start fail
        log(cfg, f"removed a non-directory blocking {sroot}")
    os.makedirs(d, mode=0o700, exist_ok=True)
    ended = os.path.join(d, ".ended")
    if os.path.exists(ended):
        os.unlink(ended)
    env_file = os.environ.get("CLAUDE_ENV_FILE")
    try:
        if env_file:
            with open(env_file, "a", encoding="utf-8") as f:
                f.write(f"export CLAUDE_SESSION_TMP={shlex.quote(d)}\nexport CLAUDE_SESSION_ID={shlex.quote(sid)}\n")
    except OSError as e:
        log(cfg, f"could not write CLAUDE_ENV_FILE: {e}")
    archive = tilde(os.path.join(HERE, "archive.py"))
    index = os.path.join(cfg["archive_root"], "INDEX.md")
    say(f"[file-lifecycle] Session scratch dir: {tilde(d)} ($CLAUDE_SESSION_TMP) — "
        f"deleted {cfg['session_grace_hours']}h after the session ends. To keep a file, "
        f"`python3 {archive} add` it; before creating a long-lived file, look in {index}.")
    try:
        owner = claude_ancestor()
    except Exception as e:  # a failed lookup only weakens the liveness check; never block a session
        log(cfg, f"claude process lookup failed: {type(e).__name__}: {e}")
        owner = None
    meta = {"session_id": sid, "transcript_path": data.get("transcript_path", ""),
            "cwd": data.get("cwd", ""), "source": data.get("source", ""), "started": int(time.time()),
            "claude": owner}
    with open(os.path.join(d, ".meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False)
    if not args.no_sweep and not err:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "sweep"],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    return 0


def cmd_session_end(_args):
    cfg, _err = load_config()
    data = read_hook_input()
    d = session_dir(cfg, data.get("session_id", ""))
    if not d or not os.path.isdir(d) or os.path.islink(d):
        return 0
    real = [n for n in os.listdir(d) if n not in (".meta.json", ".ended")]
    if not real:
        shutil.rmtree(d, ignore_errors=True)
        return 0
    with open(os.path.join(d, ".ended"), "w", encoding="utf-8") as f:
        f.write(f"{int(time.time())} {data.get('reason', '')}\n")
    return 0


# ---------- sweep ----------

def newest_mtime(path):
    """Most recent mtime anywhere in the tree (symlinks are not followed)."""
    newest = os.lstat(path).st_mtime
    if os.path.isdir(path) and not os.path.islink(path):
        for d, dirs, files in os.walk(path, followlinks=False):
            for n in dirs + files:
                try:
                    newest = max(newest, os.lstat(os.path.join(d, n)).st_mtime)
                except OSError:
                    pass
    return newest


def tree_size(path):
    total = 0
    try:
        if os.path.isdir(path) and not os.path.islink(path):
            for d, _, files in os.walk(path, followlinks=False):
                for n in files:
                    try:
                        total += os.lstat(os.path.join(d, n)).st_size
                    except OSError:
                        pass
        else:
            total = os.lstat(path).st_size
    except OSError:
        pass
    return total


def busy_paths(root):
    """Paths under root that a process holds open or uses as cwd. None means "unknown" (treat all as busy)."""
    stub = os.environ.get("FILE_LIFECYCLE_BUSY_STUB")
    if stub is not None:
        return None if stub == "FAIL" else {p for p in stub.split(os.pathsep) if p}
    lsof = os.environ.get("FILE_LIFECYCLE_LSOF")
    if lsof is None:
        lsof = shutil.which("lsof") or ("/usr/sbin/lsof" if os.path.exists("/usr/sbin/lsof") else "")
    if not lsof or not os.path.exists(lsof):
        return None
    try:
        proc = subprocess.run([lsof, "-nP", "-Fn"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    if not proc.stdout:
        return None
    prefix = root + os.sep
    return {line[1:] for line in proc.stdout.splitlines() if line.startswith("n") and line[1:].startswith(prefix)}


def is_busy(path, busy):
    if busy is None:
        return True
    p = path + os.sep
    return any(b == path or b.startswith(p) for b in busy)


def is_bare_repo(d, names):
    return "HEAD" in names and os.path.isdir(os.path.join(d, "objects")) and os.path.isdir(os.path.join(d, "refs"))


def has_git(path):
    if not os.path.isdir(path) or os.path.islink(path):
        return False
    for d, dirs, files in os.walk(path, followlinks=False):
        if ".git" in dirs or ".git" in files or is_bare_repo(d, files):
            return True
        dirs[:] = [x for x in dirs if x not in ("node_modules", ".venv", "venv")]
    return False


def remove(path, root, dry, report, why, still_true=None):
    real_parent = os.path.realpath(os.path.dirname(path))
    if not (real_parent == root or real_parent.startswith(root + os.sep)):
        report.append(f"SKIP(outside root) {path}")
        return
    size = tree_size(path)
    if still_true and not still_true():  # e.g. the session resumed while the tree was being walked
        report.append(f"SKIP(changed during sweep) {os.path.relpath(path, root)}")
        return
    report.append(f"{'WOULD-DELETE' if dry else 'DELETE'} {os.path.relpath(path, root)} ({size // 1024}KB, {why})")
    if dry:
        return
    try:
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path, ignore_errors=True)
        else:
            os.unlink(path)
    except FileNotFoundError:
        pass


def match_entry(name, entries):
    for e in entries:
        if fnmatch.fnmatch(name, e["pattern"]):
            return e
    return None


def session_alive(sdir, now, idle_days):
    try:
        with open(os.path.join(sdir, ".meta.json"), encoding="utf-8") as f:
            meta = json.load(f)
    except (OSError, ValueError):
        return False
    if not isinstance(meta, dict):
        return False
    owner = meta.get("claude")
    if isinstance(owner, dict) and isinstance(owner.get("pid"), int) and owner.get("lstart") \
            and proc_start(owner["pid"]) == owner["lstart"]:
        return True
    tp = meta.get("transcript_path", "")
    return bool(isinstance(tp, str) and tp and os.path.exists(tp) and now - os.path.getmtime(tp) < idle_days * DAY)


def is_session_dir(sid, sdir):
    """Only dirs this tool created: a session-id name plus its own marker files. Anything else under s/
    (a user's folder, an unpacked tree with old mtimes) is left alone."""
    return bool(SID_RE.match(sid)) and (os.path.exists(os.path.join(sdir, ".meta.json"))
                                         or os.path.exists(os.path.join(sdir, ".ended")))


def load_seen(cfg, root):
    try:
        with open(os.path.join(root, ".seen.json"), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        log(cfg, ".seen.json is malformed; starting a new ledger")
        return {}
    return data


def save_seen(root, seen):
    p = os.path.join(root, ".seen.json")
    with open(p + ".new", "w", encoding="utf-8") as f:
        json.dump(seen, f)
    os.replace(p + ".new", p)


def sweep(cfg, dry=False):
    root = expand(cfg["tmp_root"])
    now = time.time()
    report = []
    if not os.path.isdir(root):
        return report
    busy = busy_paths(root)
    grace = cfg["session_grace_hours"] * 3600
    idle = cfg["session_idle_days"]
    seen = load_seen(cfg, root)
    present = set()

    def first_seen(key, path):
        """When the sweeper first saw this entry. A new inode under the same name (deleted and
        unpacked again) counts as a new entry."""
        present.add(key)
        ino = os.lstat(path).st_ino
        rec = seen.get(key)
        if not (isinstance(rec, list) and len(rec) == 2 and rec[1] == ino):
            rec = [rec, ino] if isinstance(rec, (int, float)) else [now, ino]
            seen[key] = rec
        return rec[0]

    def old_enough(key, path, ttl_days):
        first = first_seen(key, path)
        return now - first >= ttl_days * DAY and now - newest_mtime(path) >= ttl_days * DAY

    def guarded(path, label, why, still_true=None):
        if has_git(path):
            report.append(f"KEEP(contains git — check by hand) {label}")
        else:
            remove(path, root, dry, report, why, still_true)

    sroot = os.path.join(root, "s")
    if os.path.isdir(sroot) and not os.path.islink(sroot):
        for sid in sorted(os.listdir(sroot)):
            sdir = os.path.join(sroot, sid)
            try:
                if os.path.islink(sdir) or not os.path.isdir(sdir) or is_busy(sdir, busy):
                    continue
                if not is_session_dir(sid, sdir):
                    report.append(f"SKIP(not a session dir) s/{sid}")
                    continue
                ended_p = os.path.join(sdir, ".ended")
                if os.path.exists(ended_p):
                    if now - os.path.getmtime(ended_p) >= grace:
                        guarded(sdir, f"s/{sid}", "grace period after session end",
                                lambda p=ended_p: os.path.exists(p))
                elif not session_alive(sdir, now, idle) and now - newest_mtime(sdir) >= idle * DAY:
                    guarded(sdir, f"s/{sid}", "abandoned without an end marker")
            except Exception as e:  # one bad dir must not stop the rest of the sweep
                report.append(f"ERROR s/{sid}: {type(e).__name__}: {e}")

    if cfg["sweep_top_level"]:
        for name in sorted(os.listdir(root)):
            if name == "s" or name.startswith("."):
                continue
            path = os.path.join(root, name)
            try:
                entry = match_entry(name, cfg["entries"])
                policy = entry.get("policy", "keep") if entry else "ttl"
                ttl_days = entry.get("ttl_days", cfg["default_ttl_days"]) if entry else cfg["default_ttl_days"]
                if policy not in POLICIES or policy == "keep":  # an unknown policy keeps: fail closed
                    continue
                if policy == "ttl-contents":
                    if not os.path.isdir(path) or os.path.islink(path):
                        continue
                    for child in sorted(os.listdir(path)):
                        cp = os.path.join(path, child)
                        if is_busy(cp, busy):
                            first_seen(f"{name}/{child}", cp)
                            continue
                        if old_enough(f"{name}/{child}", cp, ttl_days):
                            guarded(cp, f"{name}/{child}", f"inside {name}, {ttl_days}d old")
                    continue
                if is_busy(path, busy):
                    first_seen(name, path)
                    continue
                if not old_enough(name, path, ttl_days):
                    continue
                guarded(path, name, f"unregistered, unused {ttl_days}d" if not entry else f"registered ttl {ttl_days}d")
            except Exception as e:  # one bad entry must not stop the rest of the sweep
                report.append(f"ERROR {name}: {type(e).__name__}: {e}")

    if not dry:
        save_seen(root, {k: v for k, v in seen.items() if k in present and os.path.lexists(os.path.join(root, k))})
    return report


def cmd_sweep(args):
    cfg, err = load_config()
    if err:
        log(cfg, f"config error, nothing swept: {err}")
        if args.dry_run:
            print(f"config error, nothing will be swept: {err}")
        return 0
    root = expand(cfg["tmp_root"])
    if not os.path.isdir(root):
        if args.dry_run:
            print("nothing to sweep")
        return 0
    lock = open(os.path.join(root, ".sweep.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        if args.dry_run:
            print("another sweep is running — check again shortly")
        return 0
    stamp = os.path.join(root, ".sweep-stamp")
    if not args.force and not args.dry_run and os.path.exists(stamp) \
            and time.time() - os.path.getmtime(stamp) < cfg["throttle_hours"] * 3600:
        return 0
    if not args.dry_run:
        with open(stamp, "w") as f:
            f.write(str(int(time.time())))
    try:
        report = sweep(cfg, dry=args.dry_run)
    except Exception as e:  # stderr is discarded in the background, so leave a trace in the log
        log(cfg, f"ERROR sweep: {type(e).__name__}: {e}")
        raise
    for line in report:
        if args.dry_run or args.verbose:
            print(line)
        if not args.dry_run:
            log(cfg, line)
    if args.dry_run:
        if not report:
            print("nothing to sweep")
        if not cfg["sweep_top_level"]:
            print("(top-level sweep is off — only session dirs are managed; set sweep_top_level to enable)")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Claude Code scratch-file lifecycle")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("session-start")
    s.add_argument("--no-sweep", action="store_true")
    s.set_defaults(fn=cmd_session_start)
    sub.add_parser("session-end").set_defaults(fn=cmd_session_end)
    w = sub.add_parser("sweep")
    w.add_argument("--dry-run", action="store_true")
    w.add_argument("--force", action="store_true")
    w.add_argument("--verbose", action="store_true")
    w.set_defaults(fn=cmd_sweep)
    st = sub.add_parser("status")
    st.set_defaults(fn=lambda _a: cmd_sweep(argparse.Namespace(dry_run=True, force=True, verbose=True)))
    args = p.parse_args(argv)
    try:
        return args.fn(args)
    except Exception as e:  # a hook must never block a session from starting or ending
        if args.cmd in ("session-start", "session-end"):
            log(load_config()[0], f"ERROR {args.cmd}: {type(e).__name__}: {e}")
            return 0
        raise


if __name__ == "__main__":
    sys.exit(main())
