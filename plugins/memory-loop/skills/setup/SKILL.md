---
name: setup
description: First-time memory-loop setup — offer identity names, create HABITS.md from the template, write an initial config, and verify the hooks respond.
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
- Then *suggest* (do not apply) adding an import line to the user's own
  `~/.claude/CLAUDE.md` so the habits load into every session — show them the
  exact line and let them add it:
  ```
  @groundwork/HABITS.md
  ```
  (The path is relative to `~/.claude/`. Never edit the user's CLAUDE.md
  yourself.) Import **only** HABITS.md — HABITS-CASES.md and HABITS-ARCHIVE.md
  are deliberately left out so their prose is not re-read on every request.

  An unimported habit file is the quiet failure mode of this whole loop: it
  still collects rules, and none of them ever reach a session. If the user
  declines the import, say plainly that capture will keep running with no
  effect, and offer to skip habit capture entirely instead.

## 3. Config

Offer to copy the example config to the global location:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/examples/memory-loop.example.json" ~/.claude/groundwork/memory-loop.json
```

Explain the four keys before copying:
- `nudgeInterval` — the learning-review nudge fires every N responses
  (default 10; raise it for less frequent reviews).
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
printf '{"stop_hook_active": false}' | bash "${CLAUDE_PLUGIN_ROOT}/hooks/learning-nudge.sh"
```

Expected: identity prints either the configured names or the setup offer; the
sweep prints nothing (or a report if something already lapsed); the nudge
prints nothing on a first run (it fires every N responses).

Finish by pointing at the two everyday skills: `remember` (the save gate for
memories) and `habit` (distilling lessons into HABITS.md).
