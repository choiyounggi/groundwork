---
name: consolidate
description: Periodically merge the memory index, long-tier memory files, and the habit file — deduplicate, resolve contradictions to the current truth, absolutize dates, bring HABITS.md back under budget — and propose the result for your confirmation before any write. Use when MEMORY.md grows large (~120+ lines), when the habit file is over budget, or when memories accumulate duplicates, contradictions, or stale facts.
---

# memory-loop: consolidate

Capture and expiry keep memory *flowing*; nothing keeps it *coherent*. Over many
sessions the index bloats, two files describe the same thing, an old fact
survives next to the newer one that disproved it, and "yesterday" is frozen in a
note whose yesterday is long gone. This skill is the operate-stage cleanup: a
reflective pass that merges long-tier memory into durable, well-organized form —
and, like `remember`, **never writes without your confirmation**.

> Adapted from xai-org/grok-build's "dream" consolidation pass (Apache-2.0),
> reframed around memory-loop's save gate and tier model.

## When to run

It is a manual skill — there is no forced trigger. Run it when:

- `MEMORY.md` has grown large (~120+ lines).
- A learning-review nudge surfaced duplicate or contradictory notes.
- A big piece of work finished and left several related memories behind.
- The learning-nudge hook reported HABITS.md over budget, or a write to it was
  denied by `habits-budget-guard.sh`.

## Scope — what it may touch

Read `MEMORY.md`, the `tier: long` memory files beside it, and the habit file
(`habitsPath`, default `~/.claude/groundwork/HABITS.md`). **Exclude:**

| Excluded | Why |
|----------|-----|
| Files without a `tier` key | Outside the lifecycle (the compatibility contract) — never touch them |
| `tier: short` memories | The expiry sweep owns these; consolidation leaves them alone |
| Identity files (the user/assistant names from `setup`) | Continuity anchors — changed only through the `identity` skill, never here |
| Anything already under `archived/` | Already retired |

## The five verbs

Review each memory or group through five lenses (the consolidation prompt):

1. **Merge** — fold related information into one coherent, self-contained topic.
2. **Resolve** — on a contradiction, keep only the current truth; a recent
   session that disproves an older fact wins (note the superseded one as
   background if it still explains a decision).
3. **Convert** — turn relative dates ("yesterday", "last week") into absolute
   dates.
4. **Discard** — drop ephemera: greetings, meta-commentary, tool-output noise,
   consumed "current state / next steps", and preferences already in global
   memory. **Discard means move to `archived/`, not delete** — nothing is lost.
5. **Preserve** — keep decisions and their rationale, architecture, preferences,
   and problem/solution pairs.

## The habit pass

HABITS.md is consolidated by the same five verbs, with one extra constraint: it
has a hard budget (`habitsBudgetBytes`, default 8000; `habitsMaxRules`, default
24) that a PreToolUse guard enforces at the write. Capture has an automatic
trigger and pruning does not, so without this pass the file only ever grows.

- **Merge by trigger, not by wording.** Two rules that fire in the same moment
  are one rule however differently they are phrased. A cluster of rules that all
  say "check the real artifact before claiming it" in the vocabulary of
  different incidents is the single most common way the file fills up.
- **Re-apply the three gates** (damage / recurrence / generality) to every
  existing rule, not just to new ones. A rule that names one script, one flag,
  or one repo's layout fails generality now even if it passed when it was
  written — route it to that repo's `CLAUDE.md` or the wiki.
- **Discard means archive**, exactly as for memories: move the rule to
  `HABITS-ARCHIVE.md` beside HABITS.md, keeping its `[Cnn]` pointer so the case
  record still resolves. Never touch HABITS-CASES.md itself — the cases outlive
  the rules that cited them.
- **Never reword a rule while relocating it.** Moving and editing in the same
  step is the hardest kind of change to review afterwards.
- Report the before/after of both numbers: bytes and rule count.

🛑 hard lines are consolidated, never dropped for budget: merge overlapping
prohibitions and compress their inline background to one sentence, but a
prohibition leaves this file only when it is promoted to a hook that enforces it.

## Procedure

1. **Read** (read-only) `MEMORY.md`, the in-scope long-tier files, and — when
   this run includes the habit pass — all of HABITS.md.
2. **Apply the five verbs** and draft a **per-file action table** — no writing yet:

   ```
   | File            | Action                    | Basis (one line)                       |
   |-----------------|---------------------------|----------------------------------------|
   | a.md + b.md     | merge → topic-x.md         | same topic X in both; b is newer       |
   | c.md            | evolve (edit in place)     | 3 relative dates → absolute; 1 Resolve |
   | d.md            | archive                    | consumed project note; gist now global |
   | e.md            | keep                       | still valid, unchanged                 |
   ```

   Include the before/after of each `MEMORY.md` index line that changes.
3. **Refuse the degenerate case.** If the table is empty — nothing genuinely
   merges, contradicts, or staled — report "nothing to consolidate" honestly.
   Never invent consolidation to look productive.
4. **Confirm before writing.** Present the table and ask the user to approve
   all / pick items / reject. Flag any uncertain call (especially *which side of
   a contradiction is current*) as a question, not a decision. **No `Write`/`Edit`
   before this confirmation.**
5. **Apply only what was approved.** For each merge: create the merged file, move
   the originals to `archived/`, update the `MEMORY.md` index line, and fix any
   `[[wikilink]]` references to renamed files (grep to confirm none dangle).
   Preserve every frontmatter key (`tier`, `salience`, `expires`, …) on the
   surviving file.
6. **Report** what changed: N actions applied, index N → N lines.

## Safety contract

- Propose, then write — the confirmation in step 4 is the only path to a write.
- Never delete; archive instead (restore is a `mv` plus a save-gate re-save).
- Never bulk-add `tier` to untiered files here; that is the `remember` gate's job.
- An unverified inference is not consolidated — the same rule the save gate
  applies at the entrance, applied again when reorganizing.
