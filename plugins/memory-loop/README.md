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
  into standing behavior (positive practices 🟢, hard lines 🛑).
- **Identity** — a one-time, declinable offer to set names for the user *and*
  the assistant (the assistant may pick its own name), injected as context
  every session. Continuity you can address by name.

## Install

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install memory-loop@groundwork
```

Then run the `setup` skill (ask for "set up memory-loop") — it walks through
identity, HABITS.md, and config, and verifies the hooks respond.

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

## Skills

| Skill | Purpose |
|-------|---------|
| `setup` | First-time walkthrough: identity → HABITS.md → config → verify |
| `identity` | Set, change, or decline the user/assistant names |
| `remember` | The save gate: evidence check → tier confirm → expiry confirm → write |
| `consolidate` | Periodically merge long-tier memory — dedupe, resolve contradictions to the current truth, absolutize dates — proposed for your confirmation before any write; discards to `archived/`, never deletes |
| `habit` | Distill a lesson into HABITS.md (🟢 practice / 🛑 hard line), merge over multiply, escalate to hooks/skills when warranted |

## Configure

Optional. Copy `examples/memory-loop.example.json` to
`~/.claude/groundwork/memory-loop.json` (global) or
`<repo>/.groundwork/memory-loop.json` (repo, team-shared). Repo overrides
global overrides built-in defaults.

| Key | Default | Meaning |
|-----|---------|---------|
| `nudgeInterval` | `10` | Fire the learning-review nudge every N responses |
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
