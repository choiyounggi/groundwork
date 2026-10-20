---
name: remember
description: Save gate for persistent memories — confirm tier (long/short) and expiry with the user before writing, so hallucinated or transient facts never enter long-term memory. Use whenever saving a memory file, and when the expiry sweep reports archived memories.
---

# memory-loop: remember

A wrongly saved memory gets recalled later *as if it were fact* — that is one
of the biggest sources of persistent hallucination. This gate blocks it at the
entrance.

## The gate (in order, before any write)

1. **State the candidate and its evidence.** What exactly would be saved, and
   how was it verified? An unverified inference is never saved — verify it
   first or drop it.
2. **Confirm the tier with the user:**
   - `tier: long` — keeps applying indefinitely (identity, policies,
     infrastructure facts, recurring preferences).
   - `tier: short` — consumed by a date or an event (schedules, in-flight
     work, decisions pending).
3. **If short, agree on the expiry:**
   - Absolute: `expires: YYYY-MM-DD`. The expiry sweep archives it on the
     first session *after* that date has passed — the expiry day itself is
     still live (exclusive boundary).
   - Conditional: `expires_when: "<event>"` (e.g. "after the release ships").
     Never auto-archived; you review it manually when the event happens.
4. **Write the memory file in the native format** — the usual frontmatter
   (`name`, `description`, `metadata`) — adding the lifecycle keys under
   `metadata`:

   ```markdown
   ---
   name: deploy-freeze-january
   description: Deploys are frozen until the audit completes
   metadata:
     type: project
     tier: short
     expires: 2026-02-01
   ---

   <the fact>
   ```

5. **Update the memory index** (`MEMORY.md` in the same directory) with a
   one-line pointer — the *when to recall it* hook, not the fact itself. Keep
   it to one short line (about 150 characters) with no sub-bullets; numbers,
   dates and history belong in the body. The index is loaded on every request
   and the body is not, so detail in the index is paid per turn, and the
   `memoryIndexMaxLines` check cannot see a line that has grown into a
   paragraph.

## What not to save

Most candidates should be dropped here, before step 1:

- **It already lives in an always-loaded file or is enforced elsewhere.** A
  rule that CLAUDE.md, an imported rules file, a hook or a skill already
  states is not a memory. A copy costs tokens on every request and drifts from
  its source the first time either one is edited — keep a single source.
- **It is a lesson about how to act.** That is a habit candidate
  (`memory-loop:habit`, with its own gates), not a fact.
- **It is the state of in-flight work.** Save it as `tier: short` with an
  `expires_when:` naming the event that ends it (a release, a merge, a
  decision), so the upkeep check can ask whether that event has happened.
  When it ends, archive it; carry forward only a lesson general enough to
  clear the habit gates.
- **A memory on the same subject already exists.** Update that file instead
  of adding a sibling.

Optional: `salience: 1-5` (recall priority) may be added under `metadata`;
memory-loop does not enforce it — it is a hint for your own recall ordering.

## Keeping the dates honest

Two `metadata` dates drive the upkeep check, and both are cheap:

- `modified: YYYY-MM-DD` — set it whenever you change a memory's **content**.
  Editing the body while leaving this stale is what makes an index line and a
  file disagree without anything noticing.
- `reviewed: YYYY-MM-DD` — set it when you **re-verified** a memory and it was
  still true, with nothing to change. Without this there is no way to say "I
  checked, it holds", so the same file is flagged forever and the check trains
  you to ignore it.

Re-verification means you ran the command or read the source again — not that
the memory still sounds plausible.

## Compatibility contract

Files without a `tier` key are **outside the lifecycle** — the sweep never
touches them. That is the safe default for every memory that existed before
this plugin was installed. Never bulk-add `tier` to old files; tier them one
by one, through this gate, as they come up.

## When the upkeep check reports

The SessionStart upkeep check names memories untouched past
`memoryReviewDays`, index drift, orphans and broken index links. It never
writes. Offer `/memory-loop:consolidate` for anything it lists — except:

- **Untiered files.** Consolidation may not touch them (the compatibility
  contract above). Re-verify the fact yourself, then bring it through this gate
  as a tiered memory, or leave it exactly as it is.
- **`tier: short` with a conditional or missing expiry.** Nothing archives
  these — the sweep only acts on an absolute `expires:`. The question is not
  "is it old" but "did the event already happen": if it did, archive it; if it
  did not, leave it and set `reviewed:`; if it never will, convert it to
  `tier: long` or give it an absolute date, through this gate.
- **A memory that is simply old.** Age is not wrongness. If it still holds,
  the whole repair is one `reviewed:` line.

## When the sweep reports

The expiry sweep prints which files it moved to `archived/`. Then:

1. Remove the corresponding index lines from that directory's `MEMORY.md`
   (the file bodies are preserved in `archived/` — nothing is lost).
2. For any archived fact that is *still valid*, offer the user a promotion:
   restore it from `archived/` and re-save it as `tier: long` — through this
   gate, with their confirmation.
