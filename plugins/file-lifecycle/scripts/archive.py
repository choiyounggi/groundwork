#!/usr/bin/env python3
"""Long-term archive for files worth keeping past a session — add, find, check, and an INDEX.md navigator.

Layout (root: `archive_root` in the config, default ~/claude-archive):
  <category>/<YYYY-MM-DD>_<slug><ext>   archived files and directories
  index.jsonl                           source of truth, one entry per line
  INDEX.md                              navigator generated from index.jsonl (do not edit by hand)

Usage:
  archive.py add <src>... --cat reports --topic "what" --why "why it exists and when to reuse it"
                 [--slug x] [--ticket K] [--review YYYY-MM-DD] [--copy] [--allow-unscanned] [--accept-hit PATH]
  archive.py find <term>...
  archive.py check          drift between index and files, overdue reviews (exit 1 on problems)
  archive.py remove <path> --yes
  archive.py rebuild        regenerate INDEX.md
  archive.py rehash         recompute every sha256 (once, after the hashing scheme changes)

The secret scan before archiving fails closed: a file that cannot be scanned (too large, unknown
binary, unreadable archive) is refused too, and passes only with --allow-unscanned after a human
looked at it. The archive outlives session logs and gets copied around by hand.
Content that is already archived (same sha256) is refused — preventing duplicates is the point of
the navigator.
"""
import argparse
import bz2
import datetime
import fcntl
import gzip
import hashlib
import io
import json
import lzma
import os
import re
import shutil
import sys
import tarfile
import zipfile

from lifecycle_config import expand, load_config

CATEGORIES = {
    "reports": "analyses, reports, dashboards (HTML/MD)",
    "plans": "designs, plans, specs",
    "data": "extracts, snapshots, inventories",
    "backups": "recovery backups (settings, policies, uncommitted work)",
    "notes": "handoffs, notes, investigation records",
    "scripts": "scripts and queries worth reusing",
}

# Report pattern names only, never the matched value.
SECRET_PATTERNS = [
    ("aws-access-key", re.compile(rb"AKIA[0-9A-Z]{16}")),
    ("aws-secret-key", re.compile(rb"(?i)aws_?secret_?access_?key[\"']?\s*[=:]\s*[\"']?[A-Za-z0-9/+=]{30,}")),
    ("private-key", re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("jwt", re.compile(rb"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}")),
    ("slack-token", re.compile(rb"xox[abprs]-[A-Za-z0-9-]{10,}")),
    ("slack-webhook", re.compile(rb"hooks\.slack\.com/services/[A-Za-z0-9/]+")),
    ("github-token", re.compile(rb"gh[pousr]_[A-Za-z0-9]{30,}")),
    # The scheme length is capped: an unbounded `[A-Za-z0-9+.-]*` rescans from every position of a
    # long alphanumeric run (a hex dump) and goes quadratic.
    ("url-credentials", re.compile(rb"\b[A-Za-z][A-Za-z0-9+.-]{0,30}://[^/\s:@\"']+:[^@\s/\"']{3,}@")),
    ("bearer-token", re.compile(rb"(?i)\bbearer[ \t]+[A-Za-z0-9._~+/=-]{16,}")),
    # The value must be an ASCII literal on the same line followed by a delimiter. `token = get_token()`,
    # `password = os.environ[...]`, the line after `if token:`, `<YOUR_PASSWORD>` and prose are not
    # secrets, and matching them would make ordinary scripts impossible to archive.
    ("password-assignment", re.compile(
        rb"(?i)[\"']?\b(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|secret[_-]?access[_-]?key|"
        rb"access[_-]?token|client[_-]?secret|private[_-]?key)[\"']?[ \t]*[=:][ \t]*[\"']?"
        rb"[A-Za-z0-9_\-./+=@#%!*~^]{8,}(?=[\s'\",;&}]|\Z)")),
]
# OTP names are matched only between delimiters so ordinary words ("footprint", "hotplate") pass.
SECRET_NAME = re.compile(r"(?i)(token|secret|creds?\b|credential|password|passwd|\.pem$|\.key$|^\.env|cookie|jdbc|"
                         r"(^|[-_.])(t?otp|mfa)([-_.]|$))")
# Media and office-embedded images: unreadable as text but rarely hold secrets — let the binary
# through (the pattern scan still runs).
MEDIA_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp", ".tif", ".tiff", ".heic",
             ".pdf", ".mp4", ".mov", ".mp3", ".wav", ".m4a", ".woff", ".woff2", ".ttf", ".otf",
             ".emf", ".wmf", ".wdp"}
OFFICE_BIN = re.compile(r"(^|/)printerSettings\d*\.bin$")
APPLEDOUBLE_MAGIC = b"\x00\x05\x16\x07"
SCAN_LIMIT = 5 * 1024 * 1024
TOTAL_BUDGET = 50 * 1024 * 1024
MAX_DEPTH = 3
UNSCANNED = {"too-large-to-scan", "unscannable-binary", "unreadable-archive"}


def root_dir():
    cfg, err = load_config()
    if err:
        sys.exit(f"config error — fix it before using the archive: {err}")
    return expand(cfg["archive_root"])


def index_path(root):
    return os.path.join(root, "index.jsonl")


def load_index(root, strict=False):
    p = index_path(root)
    if not os.path.exists(p):
        return []
    rows, bad = [], 0
    with open(p, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                bad += 1
                print(f"index.jsonl line {n} is unreadable", file=sys.stderr)
    if bad and strict:
        sys.exit("index.jsonl is corrupt; refusing to write — fix that line first (overwriting would drop the entry).")
    return rows


class IndexLock:
    """Serialize index writes so concurrent add/remove calls do not lose each other's update."""

    def __init__(self, root):
        os.makedirs(root, exist_ok=True)
        self.fh = open(os.path.join(root, ".lock"), "w")

    def __enter__(self):
        fcntl.flock(self.fh, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fh, fcntl.LOCK_UN)
        self.fh.close()


def save_index(root, rows):
    tmp = index_path(root) + ".new"
    with open(tmp, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    os.replace(tmp, index_path(root))
    write_markdown(root, rows)


def slugify(text):
    s = re.sub(r"[^\w.-]+", "-", text.strip()).strip("-.")
    return s[:60] or "item"


def iter_files(path):
    """Yield files and symlinks (including links to directories). Symlinks are not followed."""
    if os.path.islink(path) or os.path.isfile(path):
        yield path
        return
    for d, dirs, files in os.walk(path, followlinks=False):
        dirs.sort()
        names = sorted(files + [x for x in dirs if os.path.islink(os.path.join(d, x))])
        for name in names:
            yield os.path.join(d, name)


def content_hash(path):
    """Hash with path and length delimiters — without them {a:"bc"} and {ab:"c"} collide."""
    h = hashlib.sha256()
    h.update(b"D" if os.path.isdir(path) and not os.path.islink(path) else b"F")
    base = path if os.path.isdir(path) else os.path.dirname(path)
    for f in iter_files(path):
        rel = os.path.relpath(f, base).encode() if os.path.isdir(path) else b""
        h.update(len(rel).to_bytes(8, "big") + rel)
        if os.path.islink(f):
            target = os.readlink(f).encode()
            h.update(b"L" + len(target).to_bytes(8, "big") + target)
            continue
        h.update(b"C" + os.lstat(f).st_size.to_bytes(8, "big"))
        with open(f, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()


def tree_size(path):
    return sum(os.lstat(f).st_size for f in iter_files(path))


class Unreadable(Exception):
    pass


class OverBudget(Exception):
    pass


def decompress(data):
    """The decompressed content of a single-stream compressed blob, else None."""
    try:
        if data[:2] == b"\x1f\x8b":
            return gzip.GzipFile(fileobj=io.BytesIO(data)).read(SCAN_LIMIT + 1)
        if data[:3] == b"BZh":
            return bz2.BZ2Decompressor().decompress(data, SCAN_LIMIT + 1)
        if data[:6] == b"\xfd7zXZ\x00":
            return lzma.LZMADecompressor().decompress(data, SCAN_LIMIT + 1)
    except Exception as e:  # corrupt or unsupported streams are all refused as unreadable
        raise Unreadable(type(e).__name__)
    return None


def members(data):
    """For tar/zip, yield (name, content|None) one at a time; None marks a member over SCAN_LIMIT."""
    if zipfile.is_zipfile(io.BytesIO(data)):
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    yield info.filename, zf.read(info) if info.file_size <= SCAN_LIMIT else None
        return
    try:
        tf = tarfile.open(fileobj=io.BytesIO(data))
    except tarfile.TarError:
        return
    with tf:
        for m in tf:
            if m.isfile():
                fh = tf.extractfile(m) if m.size <= SCAN_LIMIT else None
                yield m.name, fh.read() if fh else None


def spend(budget, n):
    budget[0] -= n
    if budget[0] < 0:
        raise OverBudget()


def scan_bytes(rel, name, data, hits, budget, depth=0):
    base = os.path.basename(name)
    if SECRET_NAME.search(base):
        hits.append((rel, "secret-like-filename"))
        return
    if data is None or len(data) > SCAN_LIMIT:
        hits.append((rel, "too-large-to-scan"))
        return
    spend(budget, len(data))
    if base.startswith("._") and data[:4] == APPLEDOUBLE_MAGIC:
        return  # the extended-attribute copy macOS tar adds — not user content
    if depth < MAX_DEPTH:
        try:
            inner = decompress(data)
            if inner is not None:
                scan_bytes(rel, re.sub(r"\.(gz|bz2|xz)$", "", name), inner, hits, budget, depth + 1)
                return
            found = False
            for mname, mdata in members(data):
                found = True
                scan_bytes(f"{rel}!{mname}", mname, mdata, hits, budget, depth + 1)
            if found:
                return
        except (Unreadable, OverBudget):
            raise
        except Exception as e:  # encrypted zip (RuntimeError), unsupported compression, ...
            raise Unreadable(type(e).__name__)
    if data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        data = data.decode("utf-16", errors="ignore").encode("utf-8")
    # Patterns run before the binary check — a PNG text chunk can carry a plaintext token.
    for pname, pat in SECRET_PATTERNS:
        if pat.search(data):
            hits.append((rel, pname))
            return
    if b"\0" in data[:4096] and os.path.splitext(name)[1].lower() not in MEDIA_EXT and not OFFICE_BIN.search(name):
        hits.append((rel, "unscannable-binary"))


def find_secrets(path):
    """A list of (relative path, pattern name). Values are never included."""
    hits = []
    base = path if os.path.isdir(path) else os.path.dirname(path)
    for f in iter_files(path):
        rel = os.path.relpath(f, base)
        if os.path.islink(f):
            if SECRET_NAME.search(os.path.basename(f)):
                hits.append((rel, "secret-like-filename"))
            continue
        if os.lstat(f).st_size > SCAN_LIMIT and not SECRET_NAME.search(os.path.basename(f)):
            hits.append((rel, "too-large-to-scan"))
            continue
        with open(f, "rb") as fh:
            data = fh.read(SCAN_LIMIT + 1)
        try:
            scan_bytes(rel, f, data, hits, [TOTAL_BUDGET])
        except Unreadable as e:
            hits.append((rel, f"unreadable-archive({e})"))
        except OverBudget:
            hits.append((rel, "too-large-to-scan"))
    return hits


def cmd_add(args):
    root = root_dir()
    if args.review:
        datetime.date.fromisoformat(args.review)
    today = datetime.date.today().isoformat()
    with IndexLock(root):
        rows = load_index(root, strict=True)
        known = {r.get("sha256"): r["path"] for r in rows}
        plans = []
        for given in args.src:
            given = os.path.abspath(os.path.expanduser(given))
            if not os.path.lexists(given):
                sys.exit(f"no such path: {given}")
            # A symlink is never moved — moving its target would remove an original the user did not
            # name (a repo file, say). With --copy the real target is scanned, hashed and copied
            # (scanning the link but copying the target would bypass the scan).
            if os.path.islink(given) and not args.copy:
                sys.exit(f"symlinks are not moved — use --copy to keep the real target: {given}")
            src = os.path.realpath(given)
            if src == root or src.startswith(root + os.sep):
                sys.exit(f"already inside the archive: {given}")
            if root.startswith(src + os.sep):
                sys.exit(f"cannot archive a path that contains the archive: {given}")
            hits = [h for h in find_secrets(src) if h[0] not in (args.accept_hit or [])]
            if args.allow_unscanned:
                hits = [h for h in hits if h[1].split("(")[0] not in UNSCANNED]
            if hits:
                lines = "\n".join(f"  - {rel}: {name}" for rel, name in hits[:20])
                hint = ""
                if any(h[1].split("(")[0] in UNSCANNED for h in hits):
                    hint += "\nFor a file that cannot be scanned, look at it yourself, then pass --allow-unscanned."
                if any(h[1].split("(")[0] not in UNSCANNED for h in hits):
                    hint += ("\nIf you checked a hit and it is not a secret (an example or placeholder), pass "
                             "--accept-hit <path> for that path.")
                sys.exit(f"refusing to archive — possible secrets ({given}):\n{lines}\n"
                         f"Remove the value or leave the file out, then try again.{hint}")
            digest = content_hash(src)
            if digest in known:
                sys.exit(f"the same content is already archived: {known[digest]} — reuse that file.")
            name = os.path.basename(src.rstrip(os.sep))
            stem, ext = (name, "") if os.path.isdir(src) else os.path.splitext(name)
            ext = re.sub(r"[^A-Za-z0-9.]", "", ext)
            slug = slugify(args.slug if (args.slug and len(args.src) == 1) else stem)
            taken = {p[1] for p in plans}
            dest, n = os.path.join(root, args.cat, f"{today}_{slug}{ext}"), 1
            while dest in taken or os.path.lexists(dest):
                n += 1
                dest = os.path.join(root, args.cat, f"{today}_{slug}-{n}{ext}")
            known[digest] = os.path.relpath(dest, root)
            plans.append((src, dest, digest))

        for src, dest, digest in plans:
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            if args.copy:
                if os.path.isdir(src):
                    shutil.copytree(src, dest, symlinks=True)
                else:
                    shutil.copy2(src, dest, follow_symlinks=False)
            else:
                shutil.move(src, dest)
            rel = os.path.relpath(dest, root)
            rows.append({
                "path": rel,
                "category": args.cat,
                "topic": args.topic,
                "why": args.why,
                "ticket": args.ticket or "",
                "created": today,
                "review_by": args.review or "",
                "source": src,
                "session": os.environ.get("CLAUDE_SESSION_ID", ""),
                "sha256": digest,
                "size": tree_size(dest),
                "kind": "dir" if os.path.isdir(dest) else "file",
            })
            print(f"archived: {rel}")
        save_index(root, rows)
    return 0


def cmd_find(args):
    rows = load_index(root_dir())
    terms = [t.lower() for t in args.terms]
    hit = [r for r in rows if all(t in " ".join(str(r.get(k, "")) for k in
                                                 ("path", "topic", "why", "ticket", "category")).lower() for t in terms)]
    for r in hit:
        print(f"{r['path']}\t{r['topic']}\t{r['why']}")
    if not hit:
        print("no match")
    return 0


def cmd_check(_args):
    root = root_dir()
    rows = load_index(root)
    problems = []
    indexed = set()
    today = datetime.date.today().isoformat()
    for r in rows:
        indexed.add(r["path"])
        if not os.path.lexists(os.path.join(root, r["path"])):
            problems.append(f"missing file (index only): {r['path']}")
        if r.get("review_by") and r["review_by"] < today:
            problems.append(f"review overdue ({r['review_by']}): {r['path']}")
    for cat in sorted(os.listdir(root)) if os.path.isdir(root) else []:
        cdir = os.path.join(root, cat)
        if cat.startswith(".") or not os.path.isdir(cdir):
            continue
        for name in sorted(os.listdir(cdir)):
            if name.startswith("."):
                continue
            rel = os.path.join(cat, name)
            if rel not in indexed:
                problems.append(f"not in index: {rel}")
    for p in problems:
        print(p)
    if not problems:
        print(f"ok — {len(rows)} entries")
    return 1 if problems else 0


def cmd_remove(args):
    root = root_dir()
    with IndexLock(root):
        rows = load_index(root, strict=True)
        rel = os.path.relpath(os.path.abspath(os.path.join(root, args.path)), root)
        full = os.path.join(root, rel)
        real_parent = os.path.realpath(os.path.dirname(full))
        if rel.startswith("..") or not (real_parent == root or real_parent.startswith(root + os.sep)):
            sys.exit("refusing to delete outside the archive")
        if not any(r["path"] == rel for r in rows):
            sys.exit(f"not in index: {rel}")
        if not args.yes:
            sys.exit(f"pass --yes to delete: {rel}")
        if os.path.isdir(full) and not os.path.islink(full):
            shutil.rmtree(full)
        elif os.path.lexists(full):
            os.unlink(full)
        save_index(root, [r for r in rows if r["path"] != rel])
    print(f"deleted: {rel}")
    return 0


def cmd_rehash(_args):
    root = root_dir()
    with IndexLock(root):
        rows = load_index(root, strict=True)
        for r in rows:
            full = os.path.join(root, r["path"])
            if os.path.lexists(full):
                r["sha256"] = content_hash(full)
        save_index(root, rows)
    print(f"rehashed: {len(rows)}")
    return 0


def md_cell(text):
    return str(text).replace("|", "\\|").replace("`", "'").replace("\n", " ")


def write_markdown(root, rows):
    lines = [
        "# Archive navigator",
        "",
        "> Generated — do not edit. Add and remove entries with `archive.py` (the source of truth is `index.jsonl`).",
        "> Before creating a new file, look here for one with the same purpose. If it exists, use or update it.",
        "",
        "Rules: `<category>/<YYYY-MM-DD>_<slug>` names · no secrets (scanned on add) · no duplicate content (sha256).",
        "",
    ]
    for cat, desc in CATEGORIES.items():
        items = sorted((r for r in rows if r["category"] == cat), key=lambda r: r["path"], reverse=True)
        lines.append(f"## {cat} — {desc} ({len(items)})")
        lines.append("")
        if not items:
            lines.append("_empty_")
            lines.append("")
            continue
        lines.append("| File | What | Why it exists, when to reuse | Ticket | Review by |")
        lines.append("|---|---|---|---|---|")
        for r in items:
            lines.append(f"| `{md_cell(r['path'])}` | {md_cell(r['topic'])} | {md_cell(r['why'])} | "
                         f"{md_cell(r.get('ticket', ''))} | {md_cell(r.get('review_by', ''))} |")
        lines.append("")
    tmp = os.path.join(root, "INDEX.md.new")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.replace(tmp, os.path.join(root, "INDEX.md"))


def cmd_rebuild(_args):
    root = root_dir()
    os.makedirs(root, exist_ok=True)
    write_markdown(root, load_index(root))
    print("INDEX.md rebuilt")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description="Long-term archive for files worth keeping")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add")
    a.add_argument("src", nargs="+")
    a.add_argument("--cat", required=True, choices=list(CATEGORIES))
    a.add_argument("--topic", required=True)
    a.add_argument("--why", required=True)
    a.add_argument("--slug")
    a.add_argument("--ticket")
    a.add_argument("--review", help="review date YYYY-MM-DD — `check` reports it once passed")
    a.add_argument("--copy", action="store_true", help="copy instead of move")
    a.add_argument("--allow-unscanned", action="store_true",
                   help="let through files that cannot be scanned (too large, binary, unreadable archive) "
                        "after you looked at them. Pattern hits are still refused")
    a.add_argument("--accept-hit", action="append", metavar="PATH",
                   help="mark one refused path as reviewed (an example or placeholder value). Repeatable")
    a.set_defaults(fn=cmd_add)
    f = sub.add_parser("find")
    f.add_argument("terms", nargs="+")
    f.set_defaults(fn=cmd_find)
    sub.add_parser("check").set_defaults(fn=cmd_check)
    r = sub.add_parser("remove")
    r.add_argument("path")
    r.add_argument("--yes", action="store_true")
    r.set_defaults(fn=cmd_remove)
    sub.add_parser("rebuild").set_defaults(fn=cmd_rebuild)
    sub.add_parser("rehash").set_defaults(fn=cmd_rehash)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
