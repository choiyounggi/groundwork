# Task 07: plugins/memory-loop/README.md

## Objective
A plugin README that positions memory-loop as a lifecycle layer on top of
Claude Code's native memory, documents every hook/skill/config key implemented
in tasks 01–06, and states the compatibility and privacy guarantees.

## Wiki pages (read these first, only these)
- (none — documentation; source of truth is the implemented files)

## Inputs
- `plugins/guardrails/README.md` — structure and tone to mirror (features table, config section, FAQ style)
- The implemented files from tasks 01–06 (hooks, skills, template, example config) — document what IS, not the plan
- Decisions that bind you: D3 (state exclusive expiry), D8/D9 (identity: one-time offer, declinable, no CLAUDE.md edits), D10 (native-format compatibility; untagged files untouched), D11 (archive, never delete), D14 (suggest-only import), D15 (two-axis frame)

## Steps
1. Write `plugins/memory-loop/README.md` with sections:
   - **What it is**: the lifecycle diagram in text — capture (learning nudge) → operate (save gate, `tier`/`expires` frontmatter) → retire (expiry sweep to `archived/`, never deletion) — layered on Claude Code's native file-based memory; plus the identity feature (one-time, declinable, self-chosen name supported) and the HABITS.md distillation frame.
   - **Relationship to native memory**: adds frontmatter keys, never redefines the format; files without `tier` are never touched; uninstalling leaves memories intact.
   - **Relationship to dev-loop** (one paragraph): dev-loop's knowledge loop captures *project/engineering* knowledge into a team wiki; memory-loop captures the *agent's own* working memory and habits, locally.
   - **Hooks table**: the three hooks, their events, what each injects/does.
   - **Skills table**: setup / identity / remember / habit with one-line purposes.
   - **Configuration**: `.groundwork/memory-loop.json` (repo) / `~/.claude/groundwork/memory-loop.json` (global), keys `nudgeInterval` (default 10), `extraMemoryDirs`; state dir `~/.claude/groundwork/memory-loop/`.
   - **Expiry semantics**: `expires: YYYY-MM-DD` is exclusive — the file lives through its expiry date and is archived on the first session after it has passed; `expires_when` is never auto-archived.
   - **Privacy**: fully local, nothing leaves the machine, no telemetry.
   - **Quick start**: install lines (`/plugin install memory-loop@groundwork`), then `memory-loop:setup`.

## Deliverables
- `plugins/memory-loop/README.md`

## Verify
- Checklist: every hook filename, skill name, config key, and path in the README greps to an existing implemented file/string (`grep -rn nudgeInterval plugins/memory-loop/` etc.); no Hangul; no org/personal strings (grep the README for the private org/user terms list kept outside this repo → 0)

## Out of scope
- Root README / marketplace / CI (task 08)
