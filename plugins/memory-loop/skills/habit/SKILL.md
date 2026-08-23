---
name: habit
description: Distill a lesson — a mistake, a user correction, or a praised behavior — into HABITS.md as a positive practice or a hard line. Use after the user corrects you, after an incident, or when the learning-nudge hook fires.
---

# memory-loop: habit

HABITS.md (default `~/.claude/groundwork/HABITS.md`, created by the `setup`
skill) is the frame where lessons become standing behavior. If the file is
missing, tell the user to run `/memory-loop:setup` (step 2) first.

## Classify first — the damage question

Ask: *"If this behavior fails, does damage remain?"* — production data or
infrastructure, outbound messages (chat, PRs, mail), secrets, long-term
memory, safety hooks, destructive commands, release/operations decisions.
Damage that is later repaired but already happened (costs incurred, a wrong
external post, polluted memory) counts as YES.

- **YES → 🛑 Hard line.** Write it as a strong prohibition ("Never X before
  Y"). The blank left by a prohibition *is* the safety margin.
- **NO → 🟢 Practice.** Write it positively — "when X, the best move is Y" — in
  HABITS.md, and put the origin in `HABITS-CASES.md` as a new `## Cnn` section,
  leaving a `[Cnn]` pointer on the rule. A positive rule points at the action to
  take; a bare "don't" leaves the next moment empty.
- **Ambiguous → 🛑.** Expression defaults to positive; the safety verdict
  defaults to conservative. These are different axes — warm form, strict
  verdict.

Context can flip the grade: the same verification shortcut that is 🟢 during
read-only exploration becomes 🛑 the moment its output feeds an external post,
a PR, long-term memory, or a destructive change. Judge by *where the output
goes*, not by the action alone.

## Two files: rules loaded, cases on demand

HABITS.md is imported into every session, which means it is re-read on **every
request** — its size is paid per turn, not once per session. Background prose is
what makes such a file grow without bound, so it lives in `HABITS-CASES.md`
(same directory, not auto-loaded) and each rule carries a `[Cnn]` pointer.

- Adding a practice: append `## Cnn` to HABITS-CASES.md, put `[Cnn]` on the rule.
  Number sequentially, never renumber — a stale pointer is worse than a long file.
- Adding a hard line: keep `(← background: …)` inline in HABITS.md. For a
  prohibition the origin is the judgment you need at the moment you'd cross it,
  and the 🛑 section is small by design.
- Reading: fetch a case only when the rule alone does not settle the call.

When the learning-nudge hook reports that HABITS.md crossed the split
threshold, move the background prose still sitting in 🟢 Practices out to
HABITS-CASES.md and leave pointers behind.

### Migrating a habit file that predates this layout

A HABITS.md written before the split has its backgrounds inline and no cases
file beside it. **A plugin update does not migrate it** — templates are only
copied by `setup`, which never overwrites an existing file. So the code changes
underneath while the data stays as it was; closing that gap is a deliberate step:

1. Create `HABITS-CASES.md` next to HABITS.md — re-running the `setup` skill
   drops in the template and leaves HABITS.md untouched.
2. For each 🟢 / ⚙️ entry, cut its `(← background: …)` text into a `## Cnn`
   section in the cases file and leave `[Cnn]` on the rule. Number them in the
   order the rules appear.
3. Leave 🛑 entries exactly as they are.
4. Do **not** add HABITS-CASES.md to the CLAUDE.md import — not being loaded is
   the entire point.

Relocate prose verbatim. Never reword a rule while moving its background: a
migration that edits behavior while claiming to reorganize is the hardest kind
of change to notice afterwards.

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
