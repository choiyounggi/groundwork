# file-lifecycle

**English** | [한국어](README.ko.md)

An agent leaves files everywhere: one-off scripts, intermediate outputs, logs,
cloned repos, reports. Without a rule they pile up in `~/.claude/tmp` — and the
few worth keeping are lost among them. file-lifecycle gives every file one of two
lives:

| Kind | Where | Lifetime |
|---|---|---|
| Scratch | `~/.claude/tmp/s/<session_id>/` (`$CLAUDE_SESSION_TMP`) | deleted 24 h after the session ends |
| Worth keeping | `~/claude-archive/<category>/<YYYY-MM-DD>_<slug>` | kept until you remove it; listed in `INDEX.md` |

```text
/plugin install file-lifecycle@groundwork
```

Requires `python3` (3.8+) on macOS or Linux. No other dependencies.

## How it works

1. **SessionStart** creates the session's scratch dir, exports
   `CLAUDE_SESSION_TMP` and `CLAUDE_SESSION_ID` to Bash, and adds one line of
   context telling the agent where scratch goes and how to keep a file.
2. **SessionEnd** leaves an `.ended` marker. The sweeper deletes the dir after
   the grace period (24 h). It does not delete at once because the SessionEnd
   hook has a short time budget a large tree can outrun, and a `/clear` or
   resume may need the files again. Resuming removes the marker.
3. **The sweeper** runs in the background at session start (at most every 6 h),
   so "24 h" means the first sweep after 24 h — nothing is deleted while no
   session starts. A session that crashed without a marker is deleted once its
   claude process is gone, its transcript has been idle 7 days, and the dir
   itself is 7 days old. Only dirs the plugin created (a session-id name plus its
   marker files) are managed; anything else under `s/` is left alone.
4. **The archive** (`/file-lifecycle:archive`, or `scripts/archive.py`) moves a
   file in under a dated name, records what it is and why it exists in
   `index.jsonl`, and regenerates the `INDEX.md` navigator the agent reads
   before creating a new long-lived file.

## Top-level sweep (opt-in)

Session dirs are always managed. Everything else in `~/.claude/tmp` is left alone
until you set `"sweep_top_level": true`. Tools often keep state at fixed paths
there (locks, queues, log dirs), and deleting one of those is worse than the
clutter. Turn it on after registering what must stay:

```json
{
  "sweep_top_level": true,
  "entries": [
    {"pattern": "test-queue", "policy": "keep", "why": "shared test queue state"},
    {"pattern": "launchd-logs", "policy": "ttl-contents", "ttl_days": 30, "why": "LaunchAgent log dir"},
    {"pattern": "guard-off", "policy": "ttl", "ttl_days": 1, "why": "guard-off marker that must expire"}
  ]
}
```

- `keep` — never deleted. `ttl` — the entry is deleted after `ttl_days`.
  `ttl-contents` — the directory stays, its children expire.
- Unregistered entries expire after `default_ttl_days` (7). An entry with an
  unknown or missing policy is kept. Patterns are globs on the top-level name;
  the first match wins.
- Age needs **both** the newest mtime in the tree **and** the sweeper's first
  sighting to pass the TTL. mtime alone would delete a file that arrived with an
  old mtime (`mv`, `tar -x`) on the next sweep. So right after you turn the sweep
  on, nothing is deleted until its TTL (`default_ttl_days`, or a registered
  entry's shorter `ttl_days`) has passed since the first sweep.
- `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/tmp_lifecycle.py" status` shows what the
  next sweep would delete, without deleting it. (The SessionStart context line
  prints the plugin's full script path.)

Full example: [`examples/file-lifecycle.example.json`](examples/file-lifecycle.example.json)
(it ships with `sweep_top_level: false` — flip it once the entries fit your
setup). The config lives at `~/.claude/groundwork/file-lifecycle.json`; every key
is optional. The config is validated: a wrong type (`"false"` as a string, a
number given as text, a zero TTL) or an unsafe root (relative, `/`, your home
directory, a git checkout) is an error, and an invalid config deletes nothing.

## What the sweeper never deletes

- Entries a process holds open or uses as its working directory (`lsof`). If
  `lsof` fails or is missing, nothing is deleted.
- Entries that contain a git repository — a worktree, a clone, a bare repo —
  even inside a session dir. They are reported as `KEEP(contains git)` in the
  log, because they can hold uncommitted work.
- A session dir whose claude process is still alive (PID plus start time, so a
  reused PID does not count).
- Symlink targets and anything outside the tmp root.
- Anything, if the config file exists but is invalid: the defaults have no
  `keep` entries, so sweeping with them could delete what you registered.

## The archive

```bash
A="${CLAUDE_PLUGIN_ROOT}/scripts/archive.py"
python3 "$A" find <term>                 # look first
python3 "$A" add <path> --cat reports \
  --topic "what" --why "why it exists, when to reuse it"
python3 "$A" check                       # drift, overdue reviews
python3 "$A" remove <path> --yes
```

- Categories: `reports`, `plans`, `data`, `backups`, `notes`, `scripts`.
- **Secret scan, fail-closed.** Key assignments, cloud keys, URL credentials,
  bearer tokens, JWTs, private keys, Slack and GitHub tokens, and secret-looking
  file names — in plain files, gzip/bz2/xz, tar/zip members (three levels deep)
  and UTF-16. Only pattern names are printed, never values. Files it cannot scan
  (over 5 MB, unknown binary, encrypted archive) are refused until you pass
  `--allow-unscanned`; a reviewed false positive passes with `--accept-hit <path>`.
- Identical content (sha256) is refused, so the navigator never lists two copies.
- Symlinks are not moved; `--copy` scans and copies the real target.
- Nothing is ever deleted automatically. A `--review` date makes `check` remind you.

## Tests

```bash
python3 -m unittest discover -s plugins/file-lifecycle/tests
```

Set `FILE_LIFECYCLE_TEST_DIR` to keep the test sandboxes out of the system temp dir.
