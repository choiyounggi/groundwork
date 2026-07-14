# Task 02: memory-expiry-sweep.sh + bats tests

## Objective
A SessionStart hook that moves lapsed short-tier memory files into `archived/`
(never deleting), reports what it moved, and is provably safe on everything
else. Tests prove both directions.

## Wiki pages (read these first, only these)
- wiki/platforms/shells/portable-shell-scripts.md — shebang, `set -uo pipefail`, quoting, no-eval; verify state with independent commands
- wiki/platforms/tools/bsd-vs-gnu-cli.md — why no `date -d`/`date -v`; `date +%Y-%m-%d` + lexical compare only
- wiki/testing/quality/minimum-case-set.md — normal/error/boundary set; date boundary must assert inclusive/exclusive
- wiki/testing/quality/tests-that-cannot-fail.md — every case asserts a concrete outcome; silence cases assert emptiness explicitly

## Inputs
- `plugins/guardrails/hooks/bash-guard.sh` — header-comment style, config lookup helper shape, jq stdin parsing (`.tool_input.command` pattern → here `.cwd`)
- `plugins/guardrails/tests/bash-guard.bats` — bats harness conventions (`BATS_TEST_DIRNAME`, `BATS_TEST_TMPDIR`, helper function pattern)
- Decisions that bind you: D1, D2, D3 (exclusive boundary), D4 (slug + extraMemoryDirs), D5, D10 (sweep scope), D11 (mv to archived/ + report)

## Steps
1. Write `plugins/memory-loop/hooks/memory-expiry-sweep.sh`:
   - Header comment: purpose, config precedence (D5), design notes (never deletes; conditional `expires_when` and files without `tier: short` are left alone; fail-open).
   - Read stdin JSON; `CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')`; `[ -z "$CWD" ] && CWD="$PWD"`.
   - Slug: `SLUG=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9]|-|g')`; primary dir `$HOME/.claude/projects/$SLUG/memory`.
   - Config lookup (repo `<cwd>/.groundwork/memory-loop.json` > global `~/.claude/groundwork/memory-loop.json`): read `extraMemoryDirs` array (`jq -r '.extraMemoryDirs[]?'` from the first config file that exists in precedence order), expand a leading `~` via `${d/#\~/$HOME}`, append to the dir list.
   - For each dir that exists: loop `"$dir"/*.md` (guard `[ -e "$f" ]`), skip basename `MEMORY.md`.
   - Extract frontmatter block: `awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f'`. From it read `tier:` and `expires:` values (sed, strip quotes/spaces). Require `tier` == `short` AND `expires` matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` — anything else: skip.
   - `TODAY=$(date +%Y-%m-%d)`; expire iff `[[ "$exp" < "$TODAY" ]]` (lexical, exclusive — D3).
   - On expiry: `mkdir -p "$dir/archived"` then `mv "$f" "$dir/archived/$base"`; count and collect report lines.
   - If count > 0, print an English report: header `Memory expiry sweep: N short-tier memory file(s) moved to archived/ (not deleted).`, one `  - <basename> (expired <date>, in <dir>)` line each, then two instruction lines: remove the corresponding index lines from that directory's `MEMORY.md`; if any archived fact is still valid, offer the user to promote it to `tier: long` (restore from `archived/` and re-save) — confirm with the user first.
   - Always `exit 0`.
2. Write `plugins/memory-loop/tests/expiry-sweep.bats` with a helper that builds a fake `$HOME` (`HOME="$BATS_TEST_TMPDIR/home"`), a project memory dir for a known cwd slug, memory files with given frontmatter, and runs the hook with stdin `{"cwd": ...}` built by `jq -cn`. Cases (each asserts file location AND output):
   - normal: `tier: short`, `expires:` yesterday (compute portably: hardcode `2000-01-01`) → file moved to `archived/`, report line printed.
   - boundary (D3): `expires:` equal to today (`$(date +%Y-%m-%d)`) → NOT moved, no output.
   - `tier: long` with a past `expires` → NOT moved.
   - no `tier` key at all, past `expires` (native-memory compatibility) → NOT moved.
   - `expires_when: "after release"` conditional → NOT moved.
   - `MEMORY.md` containing a lapsed-looking frontmatter → NOT moved.
   - malformed stdin (empty string) with `$PWD` fallback resolving to a dir with a lapsed file → still sweeps (fallback works).
   - missing memory dir entirely → exit 0, empty output.
   - `extraMemoryDirs` in a global config pointing at a second dir with a lapsed file → that file is moved too.

## Deliverables
- `plugins/memory-loop/hooks/memory-expiry-sweep.sh`
- `plugins/memory-loop/tests/expiry-sweep.bats`

## Verify
- `bats plugins/memory-loop/tests/expiry-sweep.bats` → all pass
- `shellcheck -s bash plugins/memory-loop/hooks/memory-expiry-sweep.sh` → clean

## Out of scope
- learning-nudge, identity hooks (03, 04); hooks.json already done in 01
