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
- `signals.jsonl` has accumulated correction signals worth reviewing (see
  the signals pass below).
- A big piece of work finished and left several related memories behind.
- The SessionStart upkeep check (`memory-staleness-check.sh`) reported
  `habits over budget`, `habits over rule cap`, or `habits over split
  threshold` — or a write to HABITS.md was denied by
  `habits-budget-guard.sh`.
- The SessionStart upkeep check (`memory-staleness-check.sh`) listed
  re-verification candidates, index drift, orphans or broken index links — it
  is the closest thing this skill has to a trigger, and it only ever reports.

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

## The index pass

The index is a separate artifact from the memories it points at, so it drifts
on its own. All four checks are mechanical:

- **Broken links** — an index line naming a file that is not there.
- **Orphans** — a memory file no line points at; it is invisible to recall.
- **Drift** — a file newer than `MEMORY.md`: its one-line summary may describe
  a version of the body that no longer exists. Re-read the body and rewrite the
  line from it, never from the old summary.
- **Size** — past `memoryIndexMaxLines` (default 120) the index is itself the
  thing to consolidate.

## The staleness pass

Age is not wrongness. A memory past `memoryReviewDays` is a **candidate for
re-verification**, never a candidate for deletion:

1. Re-verify it the way it was verified originally — run the command, read the
   source. "It still sounds right" is not verification.
2. Still true → set `reviewed: <today>` and change nothing else. That is the
   whole repair, and it is what stops the same file being reported forever.
3. Partly wrong → correct it, set `modified: <today>`, and fix its index line.
4. Wholly superseded → archive it (never delete) and remove the index line.

Two buckets the check reports are **out of scope here** (see the exclusion
table above) — route both through `remember`: untiered files, and `tier: short`
memories whose expiry is conditional or missing, which no sweep will ever
archive and which are retired by their event, not by their age.

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

## The signals pass

`~/.claude/groundwork/memory-loop/signals.jsonl` accumulates one line per
detected correction (`hooks/correction-signal.sh`, UserPromptSubmit):
three keys only — `ts`, `session_id`, `matched` (a list of keyword
labels: 아니, 그게아니라, 틀렸, 다시해, dont, wrong) — never the prompt
text itself.

1. **Read** the file (read-only) and **group** its lines by `matched`
   label and by `session_id` — several corrections in one session on the
   same label is the strongest signal of a repeated mistake worth
   capturing.
2. **Propose** habit or memory candidates for any group that looks like a
   recurring pattern, in the same per-file action table style as the
   rest of this skill (File / Action / Basis) — never invent a candidate
   from a single isolated signal. Route each proposal through its owning
   skill (`memory-loop:habit`'s three gates, or `memory-loop:remember`'s
   save gate) rather than writing anything directly here.
3. **Confirm before truncating.** After the user approves, applies, or
   explicitly declines the proposals, truncate `signals.jsonl` to remove
   only the lines just reviewed (keep any appended after this run
   started). Never truncate before that confirmation — an unreviewed
   signal is not "handled" just because it was read.

## Procedure

1. **Read** (read-only) `MEMORY.md`, the in-scope long-tier files,
   `signals.jsonl` when this run includes the signals pass, and — when
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
7. **Record the run** so the upkeep check stops asking:

   ```bash
   mkdir -p ~/.claude/groundwork/memory-loop
   date +%Y-%m-%d > ~/.claude/groundwork/memory-loop/last-consolidate
   ```

   Write it after step 5 applied something, or after an honest "nothing to
   consolidate" in step 3 — never as a way to silence the check without
   looking.

## Safety contract

- Propose, then write — the confirmation in step 4 is the only path to a write.
- Never delete; archive instead (restore is a `mv` plus a save-gate re-save).
- Never bulk-add `tier` to untiered files here; that is the `remember` gate's job.
- An unverified inference is not consolidated — the same rule the save gate
  applies at the entrance, applied again when reorganizing.
- Age alone never justifies removing a memory. If you cannot re-verify it now,
  leave it and say so — an unverified old memory is a known risk, while a
  deleted one is a silent gap.
