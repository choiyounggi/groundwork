---
name: setup
description: First-time memory-loop setup — offer identity names, create HABITS.md and OUTPUT.md from the templates, wire their imports into ~/.claude/CLAUDE.md, write an initial config, and verify the hooks respond.
disable-model-invocation: true
---

# memory-loop: setup

Walk the user through first-time setup, in this order. Every step is optional
— respect a "skip".

## 1. Identity

Run the `identity` skill flow: offer the one-time name setup (set or decline).
See that skill for the schema and the confirmation rule.

## 2. HABITS.md

The habit-distillation frame is two files — rules that load every session, and
the case records they point to, which do not:

```
~/.claude/groundwork/HABITS.md         (imported into every session — budgeted)
~/.claude/groundwork/HABITS-CASES.md   (on demand, via [Cnn] pointers)
~/.claude/groundwork/HABITS-ARCHIVE.md (retired rules; created when first needed)
```

The habit file carries a budget — 8000 bytes / 24 rules by default — that
`habits-budget-guard.sh` enforces at the write. Mention it when you show the
file: the cap is what keeps an always-loaded file affordable, and the `habit`
skill explains how to make room.

- If they do not exist, copy the templates:
  ```bash
  mkdir -p ~/.claude/groundwork
  cp "${CLAUDE_PLUGIN_ROOT}/templates/HABITS.md" ~/.claude/groundwork/HABITS.md
  cp "${CLAUDE_PLUGIN_ROOT}/templates/HABITS-CASES.md" ~/.claude/groundwork/HABITS-CASES.md
  ```
- If either already exists, **never overwrite it** — it holds the user's
  accumulated habits. Because of that, re-running this step is also the
  migration path for a HABITS.md that predates the two-file layout: the cases
  file gets created, the habit file is left exactly as it is. (The `habit`
  skill describes how to move the prose across.)

## 2b. OUTPUT.md

A short output-style rule file — ELI5 plainness, core only, easy to scan, and
a list of what must never be trimmed (evidence, repro commands, error text).
Its goal is less reading time, less generation time, fewer tokens. Same rule
as the habit files: copy the template only if it does not exist, never
overwrite.

```bash
[ -f ~/.claude/groundwork/OUTPUT.md ] || cp "${CLAUDE_PLUGIN_ROOT}/templates/OUTPUT.md" ~/.claude/groundwork/OUTPUT.md
```

## 2c. Wire the imports into CLAUDE.md

Neither file does anything until the user's own `~/.claude/CLAUDE.md` imports
it — an unimported habit file is the quiet failure mode of this whole loop: it
still collects rules, and none of them ever reach a session. Say what the
script is about to do (one managed block, two `@` lines, a backup next to the
file), then run it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-claude-imports.sh"
```

It is idempotent: a line already present anywhere in the file (for instance
one the user added by hand earlier) is not duplicated, and a second run prints
`ok:` and writes nothing. Presence is a whole-line match, so an import quoted
inside a code fence or comment also counts — if it prints `ok:` but the user
says the file is not loading, look for that. Show the user its output,
including the backup path. It follows a symlinked CLAUDE.md to the real file
and keeps the file's mode and line endings.
Import **only** HABITS.md and OUTPUT.md — HABITS-CASES.md and HABITS-ARCHIVE.md
are deliberately left out so their prose is not re-read on every request; do
not add them by hand.

If the user declines the edit, say plainly that habit capture will keep
running with no effect, and offer to skip habit capture entirely instead. To
undo later, delete the managed block (the two `<!-- groundwork:memory-loop
… -->` markers and the lines between them).

## 3. Config

Offer to copy the example config to the global location:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/examples/memory-loop.example.json" ~/.claude/groundwork/memory-loop.json
```

Explain the four keys before copying:
- `correctionInjectionCap` — max correction-signal context injections per
  session (default 3; `0` disables injection, but every match is still
  recorded to `signals.jsonl`).
- `habitsBudgetBytes` — size budget for the always-loaded habit file (default
  8000). A write past it is denied; `0` disables the check.
- `habitsMaxRules` — rule-count cap for that file, 🟢 and 🛑 together (default
  24). This is the one that usually binds; `0` disables it.
- `extraMemoryDirs` — additional memory directories the expiry sweep should
  cover, beyond the current project's own memory directory.

The example's budget values match the hooks' built-in defaults, so copying it
changes nothing until the user edits them — say so, rather than letting the copy
look like it pinned something.

A repo can override the global config with `<repo>/.groundwork/memory-loop.json`.

## 4. Verify

Run each hook once with stub input and show the user what got injected:

```bash
printf '{}' | bash "${CLAUDE_PLUGIN_ROOT}/hooks/identity-context.sh"
printf '{}' | bash "${CLAUDE_PLUGIN_ROOT}/hooks/memory-expiry-sweep.sh"
printf '{"session_id":"setup-smoke","prompt":"that is wrong"}' | bash "${CLAUDE_PLUGIN_ROOT}/hooks/correction-signal.sh"
```

Expected: identity prints either the configured names or the setup offer; the
sweep prints nothing (or a report if something already lapsed); the
correction-signal smoke test prints one line of JSON —
`{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Correction signal: ..."}}`
— because "that is wrong" matches the `wrong` keyword.

Finish by pointing at the two everyday skills: `remember` (the save gate for
memories) and `habit` (distilling lessons into HABITS.md).
