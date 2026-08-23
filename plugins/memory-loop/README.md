# memory-loop

**English** | [한국어](README.ko.md)

**A memory lifecycle for Claude Code's native file-based memory.**

Claude Code can already *store* memories. What it lacks is a lifecycle: facts
get saved unverified (and later recalled as if true), transient notes pile up
forever, and lessons learned in one session evaporate before the next. This
plugin adds the loop around the storage:

```
capture ──────────► operate ─────────────► retire
learning nudge      save gate +            expiry sweep →
(every N replies)   tier/expires,          archived/ (never deleted)
                    consolidate
```

Plus two things a lifecycle makes possible:

- **HABITS.md** — a distillation frame that turns corrections and incidents
  into standing behavior (positive practices 🟢, hard lines 🛑). It is two
  files: the rules load every session, while their case records live in
  `HABITS-CASES.md` and are read on demand via `[Cnn]` pointers — an
  always-loaded file is re-read on every request, so it has to stay small.
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
learning-review nudge will mention the split once the file crosses
`habitsSplitWarnBytes`, and it tells you when no cases file exists yet.

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
| `memory-expiry-sweep.sh` | SessionStart | Moves lapsed `tier: short` memories into `archived/` (never deletes) and reports, so the agent tidies the index and offers promotions |
| `learning-nudge.sh` | Stop | Every N responses, reminds the agent to check the recent work for habits, skills, and memories worth persisting — each routed through the save gate |
| `tutor-due-check.sh` | SessionStart | One quiet reminder line when tutor items are due, silent otherwise |

## Skills

| Skill | Purpose |
|-------|---------|
| `setup` *(slash-command only)* | First-time walkthrough: identity → HABITS.md + HABITS-CASES.md → config → verify |
| `identity` | Set, change, or decline the user/assistant names |
| `remember` | The save gate: evidence check → tier confirm → expiry confirm → write |
| `consolidate` | Periodically merge long-tier memory — dedupe, resolve contradictions to the current truth, absolutize dates — proposed for your confirmation before any write; discards to `archived/`, never deletes |
| `habit` | Distill a lesson into HABITS.md (🟢 practice / 🛑 hard line) with its background filed in `HABITS-CASES.md` behind a `[Cnn]` pointer, merge over multiply, escalate to hooks/skills when warranted |
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
| `nudgeInterval` | `10` | Fire the learning-review nudge every N responses |
| `habitsSplitWarnBytes` | `40000` | Past this size, the nudge also asks for the habit file's background prose to move into the cases file (`0` disables) |
| `habitsPath` | `~/.claude/groundwork/HABITS.md` | The habit file the size check reads — set this if you import your own file from elsewhere (`~` supported) |
| `habitsCasesPath` | `HABITS-CASES.md` beside `habitsPath` | Where its case records live (`~` supported) |
| `extraMemoryDirs` | `[]` | Additional memory directories to sweep, beyond the current project's own (`~` supported) |

State (identity, nudge counter) lives in `~/.claude/groundwork/memory-loop/`.

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
