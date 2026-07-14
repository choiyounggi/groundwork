# Task 06: remember + habit skills

## Objective
The `remember` (save gate) and `habit` (distillation) skills exist, in English,
consistent with the sweep hook's frontmatter contract (D10) and the HABITS.md
frame (D15).

## Wiki pages (read these first, only these)
- (none — prose skill files; contracts come from Inputs)

## Inputs
- `plugins/guardrails/skills/self-test/SKILL.md` — frontmatter + tone convention
- `plugins/memory-loop/templates/HABITS.md` (task 05 deliverable) — the frame the habit skill writes into
- Decisions that bind you: D3 (exclusive expiry), D10 (frontmatter keys `tier`, `expires`, optional `expires_when`; native-memory compatibility), D14 (HABITS.md path), D15 (two-axis frame)

## Steps
1. `plugins/memory-loop/skills/remember/SKILL.md` — frontmatter `name: remember`,
   `description:` "The save gate for persistent memories: confirm tier (long/short) and expiry before writing, so hallucinated or transient facts never enter long-term memory. Use whenever saving a memory file."
   Body:
   - **Gate procedure** (in order): ① state the candidate fact and its evidence; unverified inference is never saved — verify first or drop. ② confirm with the user: `tier: long` (keeps applying indefinitely) or `tier: short` (consumed by a date or event). ③ if short: agree the expiry — absolute `expires: YYYY-MM-DD` (auto-archived by the sweep hook once the date has *passed* — the expiry day itself is still live) or conditional `expires_when: "<event>"` (never auto-archived; reviewed manually). ④ write the memory file in the native format, adding `tier` (+ `expires`/`expires_when`) to the frontmatter `metadata`; update the memory index (MEMORY.md) with a one-line pointer.
   - Note: files without `tier` are outside the lifecycle (never swept) — that is the safe default for pre-existing memories. `salience` (1–5 recall priority) may be added optionally; nothing in memory-loop enforces it.
   - When the sweep hook reports archived files: tidy the index lines it names, and for any still-valid fact offer the user a promotion to `tier: long` (restore from `archived/`, re-save through this gate).
2. `plugins/memory-loop/skills/habit/SKILL.md` — frontmatter `name: habit`,
   `description:` "Distill a lesson (a mistake, a correction, a praised behavior) into HABITS.md as a positive practice or a hard line. Use after the user corrects you, after an incident, or when the learning-nudge hook fires."
   Body:
   - **Classify first**: "If this behavior fails, does it leave damage — production data, external posts (chat/PR/mail), secrets, long-term memory, destructive commands?" YES → 🛑 hard line, written as a strong prohibition. NO → 🟢 practice, written positively ("when X, do Y best-case"), with the trigger context preserved as `(← background: date — what happened)`. **Ambiguous → 🛑** (expression defaults positive; the safety verdict defaults conservative — two different axes).
   - **Merge, don't multiply**: before adding, scan HABITS.md for an entry with an overlapping trigger; strengthen/merge it instead of appending a near-duplicate. Keep the list short and scannable.
   - **Escalation ladder**: default home is HABITS.md. If the rule prevents damage and the pattern is mechanically detectable → promote to a hook; if it is a repeatable procedure → promote to a skill; leave a one-line `→ promoted to <hook/skill>` tombstone. Promote only when clear + repeated + valuable.
   - File location: `~/.claude/groundwork/HABITS.md` (created by `setup`; if missing, offer to run setup step 2).

## Deliverables
- `plugins/memory-loop/skills/remember/SKILL.md`
- `plugins/memory-loop/skills/habit/SKILL.md`

## Verify
- Checklist: valid frontmatter in both; the frontmatter keys named (`tier`, `expires`, `expires_when`) match task 02's sweep implementation exactly; expiry semantics sentence matches D3 (exclusive); grep the skills for the private org/user terms list kept outside this repo → 0 hits; no Hangul (same grep as task 05) → 0 hits

## Out of scope
- Plugin README (07), repo integration (08)
