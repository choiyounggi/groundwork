---
name: habit
description: Distill a lesson — a mistake, a user correction, or a praised behavior — into HABITS.md as a positive practice or a hard line. Use after the user corrects you, after an incident, or when the learning-nudge hook fires.
---

# memory-loop: habit

HABITS.md (default `~/.claude/groundwork/HABITS.md`, created by the `setup`
skill) is the frame where lessons become standing behavior. If the file is
missing, offer to run setup step 2 first.

## Classify first — the damage question

Ask: *"If this behavior fails, does damage remain?"* — production data or
infrastructure, outbound messages (chat, PRs, mail), secrets, long-term
memory, safety hooks, destructive commands, release/operations decisions.
Damage that is later repaired but already happened (costs incurred, a wrong
external post, polluted memory) counts as YES.

- **YES → 🛑 Hard line.** Write it as a strong prohibition ("Never X before
  Y"). The blank left by a prohibition *is* the safety margin.
- **NO → 🟢 Practice.** Write it positively — "when X, the best move is Y" —
  and preserve the origin: `(← background: date — what happened)`. A positive
  rule points at the action to take; a bare "don't" leaves the next moment
  empty.
- **Ambiguous → 🛑.** Expression defaults to positive; the safety verdict
  defaults to conservative. These are different axes — warm form, strict
  verdict.

Context can flip the grade: the same verification shortcut that is 🟢 during
read-only exploration becomes 🛑 the moment its output feeds an external post,
a PR, long-term memory, or a destructive change. Judge by *where the output
goes*, not by the action alone.

## Merge, don't multiply

Before adding, scan HABITS.md for an entry with an overlapping trigger. If one
exists, strengthen or merge it — do not append a near-duplicate. The list only
works while it stays short and scannable.

## Escalation ladder

Default home is HABITS.md. Promote when — and only when — a rule is clear,
repeated, and valuable, all three:

- **Hard line + mechanically detectable pattern → hook** (automatic
  enforcement on every command; the main path for 🛑 entries that keep
  recurring).
- **Practice that is really a reusable procedure → skill.**

Leave a one-line tombstone in HABITS.md: `→ promoted to <hook/skill name>`.
