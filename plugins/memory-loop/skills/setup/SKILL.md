---
name: setup
description: First-time memory-loop setup — offer identity names, create HABITS.md from the template, write an initial config, and verify the hooks respond. Use right after installing the memory-loop plugin, or when asked to "set up memory-loop".
---

# memory-loop: setup

Walk the user through first-time setup, in this order. Every step is optional
— respect a "skip".

## 1. Identity

Run the `identity` skill flow: offer the one-time name setup (set or decline).
See that skill for the schema and the confirmation rule.

## 2. HABITS.md

The habit-distillation frame lives at:

```
~/.claude/groundwork/HABITS.md
```

- If it does not exist, copy the template:
  ```bash
  mkdir -p ~/.claude/groundwork
  cp "${CLAUDE_PLUGIN_ROOT}/templates/HABITS.md" ~/.claude/groundwork/HABITS.md
  ```
- If it already exists, **never overwrite it** — it holds the user's
  accumulated habits.
- Then *suggest* (do not apply) adding an import line to the user's own
  `~/.claude/CLAUDE.md` so the habits load into every session — show them the
  exact line and let them add it:
  ```
  @groundwork/HABITS.md
  ```
  (The path is relative to `~/.claude/`. Never edit the user's CLAUDE.md
  yourself.)

## 3. Config

Offer to copy the example config to the global location:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/examples/memory-loop.example.json" ~/.claude/groundwork/memory-loop.json
```

Explain the two keys before copying:
- `nudgeInterval` — the learning-review nudge fires every N responses
  (default 10; raise it for less frequent reviews).
- `extraMemoryDirs` — additional memory directories the expiry sweep should
  cover, beyond the current project's own memory directory.

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
