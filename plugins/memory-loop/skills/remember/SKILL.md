---
name: remember
description: The save gate for persistent memories — confirm tier (long/short) and expiry with the user before writing, so hallucinated or transient facts never enter long-term memory. Use whenever saving a memory file, and when the expiry sweep reports archived memories.
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
   one-line pointer.

Optional: `salience: 1-5` (recall priority) may be added under `metadata`;
memory-loop does not enforce it — it is a hint for your own recall ordering.

## Compatibility contract

Files without a `tier` key are **outside the lifecycle** — the sweep never
touches them. That is the safe default for every memory that existed before
this plugin was installed. Never bulk-add `tier` to old files; tier them one
by one, through this gate, as they come up.

## When the sweep reports

The expiry sweep prints which files it moved to `archived/`. Then:

1. Remove the corresponding index lines from that directory's `MEMORY.md`
   (the file bodies are preserved in `archived/` — nothing is lost).
2. For any archived fact that is *still valid*, offer the user a promotion:
   restore it from `archived/` and re-save it as `tier: long` — through this
   gate, with their confirmation.
