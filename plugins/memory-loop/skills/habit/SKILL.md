---
name: habit
description: Distill a lesson — a mistake, a user correction, or a praised behavior — into HABITS.md as a positive practice or a hard line, after it clears the damage/recurrence/generality gate. Use after the user corrects you, after an incident, or when a correction signal fires.
---

# memory-loop: habit

HABITS.md (default `~/.claude/groundwork/HABITS.md`, created by the `setup`
skill) is the frame where lessons become standing behavior. If the file is
missing, tell the user to run `/memory-loop:setup` (step 2) first.

It is imported into every session, so it is re-read on **every request** — its
size is paid per turn, multiplied by the length of the conversation. That is the
whole reason this skill is mostly a set of gates: a habit file that captures
everything is a file nobody can afford to load, and an unloaded habit file
teaches nothing.

## Three gates — all three, before anything is written

A lesson enters HABITS.md only when it clears all three. Answer them in order
and out loud; a candidate that fails any one of them has a better home (see the
routing table).

1. **Damage** — *"If this behavior fails, does damage remain?"* Production data
   or infrastructure, outbound messages (chat, PRs, mail), secrets, long-term
   memory, safety hooks, destructive commands, release/operations decisions.
   Damage later repaired but already done (costs incurred, a wrong external
   post, polluted memory) counts as YES. This gate decides 🛑 vs 🟢, not
   whether to write.
2. **Recurrence** — *"Has this actually happened more than once, or is there a
   named reason the next occurrence is likely?"* One incident is a case, not a
   habit. A single 🛑-grade event still qualifies — the first breach of a
   damage-remaining line is one too many — but a single 🟢-grade slip does not.
3. **Generality** — *"Does this hold outside this one tool, repo, or file?"* A
   rule naming a specific script, a specific flag's quirk, or one repo's layout
   is knowledge about that thing, not a working habit. Ask what the rule would
   say if that name were removed: if nothing is left, it fails this gate.

Context can flip gate 1: the same verification shortcut that is 🟢 during
read-only exploration becomes 🛑 the moment its output feeds an external post,
a PR, long-term memory, or a destructive change. Judge by *where the output
goes*, not by the action alone.

## Routing — where a candidate goes when it fails a gate

| Fails | Goes to | Why |
|-------|---------|-----|
| Recurrence (🟢, one-off) | nowhere — say so and move on | The cheapest correct answer. Most lessons are consumed by the session that learned them. |
| Generality (tool/flag/script-specific) | the wiki (`dev-loop:wiki-ingest`), or that tool's own docs | Retrievable when that tool is in play, absent when it is not. |
| Generality (one repo's layout, commands, conventions) | that repo's `CLAUDE.md` | Loads exactly where it applies. |
| Nothing — a fact, not a behavior | a memory (`memory-loop:remember`) | Habits are rules for acting; facts are recalled on demand. |
| All three cleared | HABITS.md | The always-loaded set. |

Routing away is the normal outcome — most sessions have nothing that
clears all three gates, and that is a complete and correct result.

## Budget — the file is capped, and the cap is enforced

`habits-budget-guard.sh` (PreToolUse) **denies** any Edit or Write that grows
HABITS.md past its budget: `habitsBudgetBytes` (default 8000) and
`habitsMaxRules` (default 24, 🟢 and 🛑 counted together). The count is the
constraint that usually binds — a list stops working as a list long before it
stops being affordable — and the byte budget catches rules that grow into essays. A write that shrinks
the file is always allowed, so the way out is never blocked.

At budget, adding means removing. In order of preference:

1. **Merge** into an existing rule with an overlapping trigger — the usual
   answer, because near-duplicates are what fill the file.
2. **Archive** a rule that no longer clears the gates: move it to
   `HABITS-ARCHIVE.md` beside HABITS.md, keeping its `[Cnn]` pointer so the case
   record still resolves. Archiving is not deletion; nothing is lost.
3. **Replace** — name the rule this one supersedes and remove it in the same
   edit.

Keep each rule to about two lines (~240 characters). A rule that needs a
paragraph is usually two rules, or one rule plus a case.

## Two files: rules loaded, cases on demand

Background prose is what makes a rule file grow without bound, so it lives in
`HABITS-CASES.md` (same directory, not auto-loaded) and each rule carries a
`[Cnn]` pointer.

- Adding a practice: append `## Cnn` to HABITS-CASES.md, put `[Cnn]` on the rule.
  Number sequentially, never renumber — a stale pointer is worse than a long file.
- Adding a hard line: keep `(← background: …)` inline in HABITS.md, but one
  sentence of it. For a prohibition the origin is the judgment you need at the
  moment you'd cross it; the incident report still belongs in the cases file.
- Reading: fetch a case only when the rule alone does not settle the call.

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
3. Compress 🛑 backgrounds to one sentence, moving the full account to the
   cases file under the same `## Cnn` number.
4. Do **not** add HABITS-CASES.md or HABITS-ARCHIVE.md to the CLAUDE.md import
   — not being loaded is the entire point.

Relocate prose verbatim. Never reword a rule while moving its background: a
migration that edits behavior while claiming to reorganize is the hardest kind
of change to notice afterwards.

## Merge, don't multiply

Before adding, read the whole of HABITS.md and look for an entry with an
overlapping **trigger** — the situation the rule fires in, not its wording. Two
rules that fire in the same moment are one rule, however different they sound.
If one exists, strengthen or merge it; do not append a near-duplicate.

The failure mode this prevents is specific and common: a dozen rules that each
say "check the real artifact before claiming" in the vocabulary of a different
incident. Merged, they are one rule anyone can hold in their head. Separate,
they are a file nobody reads.

## Escalation ladder

Default home is HABITS.md. Promote when — and only when — a rule is clear,
repeated, and valuable, all three:

- **Hard line + mechanically detectable pattern → hook** (automatic
  enforcement on every command; the main path for 🛑 entries that keep
  recurring).
- **Practice that is really a reusable procedure → skill.**

Leave a one-line tombstone in HABITS.md: `→ promoted to <hook/skill name>`.
A promotion that frees budget is the best kind of addition.
