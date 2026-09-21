# memory-loop

**English** | [한국어](README.ko.md)

**A memory lifecycle for Claude Code's native file-based memory.**

Claude Code can already *store* memories. What it lacks is a lifecycle: facts
get saved unverified (and later recalled as if true), transient notes pile up
forever, and lessons learned in one session evaporate before the next. This
plugin adds the loop around the storage:

```
capture ──────────► operate ─────────────► retire
correction signal   save gate +            expiry sweep →
(flags a mistake)   tier/expires,          archived/ (never deleted)
                    consolidate
```

Plus two things a lifecycle makes possible:

- **HABITS.md** — a distillation frame that turns corrections and incidents
  into standing behavior (positive practices 🟢, hard lines 🛑). Capture is
  gated three ways (damage → 🛑/🟢, recurrence, generality) and the file is
  **budgeted**: 8000 bytes / 24 rules, enforced at the write by a PreToolUse
  guard, because an always-loaded file is re-read on every request. Case
  records live in `HABITS-CASES.md` and retired rules in `HABITS-ARCHIVE.md`,
  neither loaded, reached via `[Cnn]` pointers.
- **Identity** — a one-time, declinable offer to set names for the user *and*
  the assistant (the assistant may pick its own name), injected as context
  every session. Continuity you can address by name.

## Install

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install memory-loop@groundwork
```

Then run `/memory-loop:setup` (slash-command only) — it walks through
identity, the habit files, and config, and verifies the hooks respond.

## Upgrading from a single-file HABITS.md

Hooks and skills update with the plugin; **your HABITS.md does not.** Templates
are only copied by `setup`, and `setup` never overwrites an existing file — so
after an upgrade the code knows about the two-file layout while your habit file
is still whatever you had. To close that gap:

1. Re-run `/memory-loop:setup` — it creates `HABITS-CASES.md` and leaves HABITS.md
   untouched.
2. Ask for the `habit` skill's migration step: move each 🟢/⚙️ entry's
   `(← background: …)` prose into a `## Cnn` section in the cases file, leaving
   `[Cnn]` on the rule. 🛑 entries stay as they are.
3. Leave your CLAUDE.md import pointing at HABITS.md only.

Doing nothing is also fine: a single-file HABITS.md keeps working. The
SessionStart memory-upkeep check will mention the split once the file
crosses `habitsSplitWarnBytes`, and it tells you when no cases file
exists yet.

## Upgrading from 1.x

The Stop-hook learning nudge is gone; `nudgeInterval` in your config is
now ignored (no warning — the key is simply unread). Its two jobs split:
the `correction-signal.sh` hook (UserPromptSubmit) now flags likely
corrections as they happen, capped by `correctionInjectionCap` (default
3), and the habit byte-budget/rule-cap/split-threshold check moved into
`memory-staleness-check.sh`'s SessionStart report, evaluated every
session. Nothing to migrate — both are active by default after the
upgrade.

## Relationship to native memory

memory-loop **extends** the native memory format; it never redefines it.

- It adds lifecycle keys under frontmatter `metadata`: `tier: long|short`,
  and for short `expires: YYYY-MM-DD` or `expires_when: "<event>"`.
- Files **without** a `tier` key are outside the lifecycle — the sweep never
  touches them. Every memory that existed before you installed the plugin is
  immune by default.
- Uninstalling leaves all memories exactly where they are.

## Relationship to dev-loop

dev-loop's knowledge loop captures *project and engineering* knowledge into a
reviewed team wiki. memory-loop captures the *agent's own* working memory and
habits, locally, per machine. They compose: one grows shared best practices,
the other grows a continuous, self-correcting agent.

## Hooks

| Hook | Event | What it does |
|------|-------|--------------|
| `identity-context.sh` | SessionStart | Injects "The user's name is X. Your name is Y." — or offers a one-time name setup when unconfigured; silent forever after a decline |
| `memory-staleness-check.sh` | SessionStart | One line naming which upkeep buckets fired (re-verify, index drift, broken links, orphans, oversized index, consolidate overdue, plus the always-on habit budget/rule-cap/split-threshold checks), pointing at `~/.claude/groundwork/memory-loop/staleness-last-detail.md` for the full report; silent when nothing to report. Reports only; never writes |
| `memory-expiry-sweep.sh` | SessionStart | Moves lapsed `tier: short` memories into `archived/` (never deletes) and prints one line naming the count, pointing at `~/.claude/groundwork/memory-loop/expiry-sweep-last.md` for the full report — so the agent tidies the index and offers promotions; silent when nothing lapsed |
| `habits-budget-guard.sh` | PreToolUse (Edit\|Write) | Denies a write that grows the habit file past its byte/rule budget; a write that shrinks it is always allowed, so the way out is never blocked |
| `correction-signal.sh` | UserPromptSubmit | When the prompt looks like a correction (Korean or English keyword), records one line to `signals.jsonl` and injects one context line suggesting a habit or memory capture — capped at `correctionInjectionCap` injections per session (default 3; every match is still recorded) |
| `tutor-due-check.sh` | SessionStart | One line when tutor items are due, naming the count and the `/memory-loop:tutor` skill; silent otherwise — no detail file needed for a single line |

## Skills

| Skill | Purpose |
|-------|---------|
| `setup` *(slash-command only)* | First-time walkthrough: identity → HABITS.md + HABITS-CASES.md → config → verify |
| `identity` | Set, change, or decline the user/assistant names |
| `remember` | The save gate: evidence check → tier confirm → expiry confirm → write |
| `consolidate` | Merge long-tier memory **and the habit file**, with an index pass (drift/orphans/broken links) and a staleness pass (re-verify, don't delete) — dedupe, resolve contradictions to the current truth, absolutize dates, bring HABITS.md back under budget — proposed for your confirmation before any write; discards to `archived/` (memories) or `HABITS-ARCHIVE.md` (rules), never deletes |
| `habit` | Distill a lesson into HABITS.md (🟢 practice / 🛑 hard line) after the damage/recurrence/generality gate, with its background filed in `HABITS-CASES.md` behind a `[Cnn]` pointer; merge over multiply, route what fails a gate to a repo CLAUDE.md or the wiki, escalate to hooks/skills when warranted |
| `tutor` | Spaced-repetition self-quiz over lessons already in HABITS.md — one novel transfer question per due item, anti-sycophancy grading, and a 1-4 recall rating |

## Tutor

`habit` turns corrections and incidents into standing practice; `tutor` closes
the loop by testing whether the practice was actually internalized.

- **Sync** — compare items already tracked (`list`) against HABITS.md's 🟢/🛑
  entries; propose new items for anything uncovered, but only after the user
  confirms each one (never bulk-generated from raw memory).
- **Quiz** — for each due item (capped at `tutorSessionCap`), ask one novel
  transfer question (never the original incident behind the lesson), grade
  against a private model answer with anti-sycophancy diagnosis before any
  verdict, ask one "why / what-if" follow-up, then let the user confirm a
  1-4 recall rating before it's recorded.
- **Reminder** — `tutor-due-check.sh` (SessionStart) prints one quiet line
  when items are due, silent otherwise.

Scheduling is Leitner box-based (5 boxes, intervals 1/3/7/21/60 days; a
rating of 1 resets to box 0, 2 holds the box, 3-4 advances it — and once an
item is at box 3 or higher, 3 consecutive rating-≥3 reviews from there retire
it). Every review is appended to a
timestamped log (`item_id`, `rating`, `ts`) — a structure an FSRS-style
scheduler could consume later without a state migration.

State lives in
`~/.claude/groundwork/memory-loop/tutor/{items.json,reviews.jsonl}`, owned
entirely by `tutor-schedule.sh` — never hand-edit it.

| Key | Default | Meaning |
|-----|---------|---------|
| `tutorSessionCap` | `3` | Max due items surfaced per `due` call (session quiz size) |
| `tutorEnabled` | `true` | Set `false` to silence the due-reminder hook and the `due` subcommand |

## Configure

Optional. Copy `examples/memory-loop.example.json` to
`~/.claude/groundwork/memory-loop.json` (global) or
`<repo>/.groundwork/memory-loop.json` (repo, team-shared). Repo overrides
global overrides built-in defaults.

| Key | Default | Meaning |
|-----|---------|---------|
| `correctionInjectionCap` | `3` | Max correction-signal context injections per session; `0` disables injection but every match is still recorded to `signals.jsonl` |
| `habitsBudgetBytes` | `8000` | Size budget for the always-loaded habit file. A write past it is denied, and the memory-upkeep check (`memory-staleness-check.sh`) reports it every session (`0` disables) |
| `habitsMaxRules` | `24` | Rule-count cap for the habit file, 🟢 and 🛑 counted together (`0` disables) |
| `habitsSplitWarnBytes` | `40000` | Past this size, the memory-upkeep check also reports that the habit file's background prose should move into the cases file (`0` disables) |
| `habitsPath` | `~/.claude/groundwork/HABITS.md` | The habit file the budget guard and size checks read — set this if you import your own file from elsewhere (`~` supported) |
| `habitsCasesPath` | `HABITS-CASES.md` beside `habitsPath` | Where its case records live (`~` supported) |
| `memoryReviewDays` | `90` | A memory untouched for this long becomes a re-verification candidate (`0` disables) |
| `memoryIndexMaxLines` | `120` | `MEMORY.md` line count that calls for a consolidation pass (`0` disables) |
| `consolidateIntervalDays` | `30` | Report when the last recorded consolidate run is older than this (`0` disables) |
| `memoryCheckCooldownDays` | `7` | Stay silent for this long after an upkeep report (`0` reports every session) |
| `extraMemoryDirs` | `[]` | Additional memory directories to sweep, beyond the current project's own (`~` supported) |

State (identity, `signals.jsonl`, `correction-sessions/`,
`expiry-sweep-last.md`, `staleness-last-detail.md`) lives in
`~/.claude/groundwork/memory-loop/`.

## Expiry semantics

`expires: YYYY-MM-DD` is **exclusive**: the memory lives through its expiry
date and is archived on the first session after the date has passed.
`expires_when: "<event>"` is never auto-archived — it marks a judgment call
the agent (and you) make when the event happens. Archived files keep their
full content under `<memory-dir>/archived/`; restoring one is a `mv` plus a
re-save through the save gate.

## Privacy

Fully local. Nothing is sent anywhere — no cloud, no telemetry, no API key.
Identity and habits are plain files on your machine that you can read, edit,
or delete at any time.

## Requirements

- `bash` 3.2+ and `jq` (same as guardrails)

## Tests

```bash
bats plugins/memory-loop/tests
```

Covered: lapsed-vs-live boundary (the expiry day itself stays live), immunity
of untiered/long/conditional/MEMORY.md files, config precedence, the
stop-hook loop guard, and fail-open behavior on malformed state.
