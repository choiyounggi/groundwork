---
name: archive
description: Keep a file past the end of the session — find an existing archived file first, then archive the new one with a dated name, a "why" line and a secret scan; or report what the scratch sweeper would delete. Use when the user asks to keep, save, archive or file away a report, plan, extract, backup or script ("keep this", "save it for later", "보관해", "남겨 둬"), when you are about to create a long-lived file, or when asked what the tmp cleanup will delete.
---

# file-lifecycle: archive

Session scratch files live in `$CLAUDE_SESSION_TMP` and are deleted after the grace
period once the session ends. Anything a later session should see goes to the
archive. The tool is `${CLAUDE_PLUGIN_ROOT}/scripts/archive.py`; the archive root is
`archive_root` in `~/.claude/groundwork/file-lifecycle.json` (default `~/claude-archive`).

## 1. Look before you create

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/archive.py" find <term>...
```

Or read `<archive_root>/INDEX.md`. If a file with the same purpose exists, use or
update that one instead of making a second copy.

## 2. Archive

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/archive.py" add <path>... \
  --cat <reports|plans|data|backups|notes|scripts> \
  --topic "what it is" --why "why it exists and when to reuse it" \
  [--slug short-name] [--ticket KEY-1] [--review YYYY-MM-DD] [--copy]
```

- Write `--why` so a reader can decide from that line alone whether to open the file:
  where it came from, and the condition under which it is reused.
- The file is moved (use `--copy` to keep the source). Symlinks are never moved.
- The tool names the file `<category>/<YYYY-MM-DD>_<slug>` and refuses content that
  is already archived.

## 3. When the secret scan refuses

The scan fails closed. Do not work around it.

- A pattern hit: remove the value from the file, or leave the file out. Pass
  `--accept-hit <path>` only after you read the hit and it is an example or a
  placeholder — never for a real value.
- "cannot be scanned" (too large, binary, unreadable archive): look at the content,
  then pass `--allow-unscanned`. Pattern hits still block.
- A file that holds a secret does not belong in the archive at all.

## 4. Maintenance

- `archive.py check` — index/file drift and overdue `--review` dates (exit 1 on problems).
- `archive.py remove <path> --yes` — only when the user asks; the archive never deletes on its own.
- `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/tmp_lifecycle.py" status` — what the next sweep
  would delete, without deleting it.
