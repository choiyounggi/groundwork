# Task 08: marketplace entry, root README, CI

## Objective
memory-loop is a first-class third plugin of the groundwork marketplace: listed
in marketplace.json, introduced in the root README, and covered by CI (bats +
shellcheck). Full-repo verification passes.

## Wiki pages (read these first, only these)
- wiki/infrastructure/ci-cd/pipeline-structure.md — where the new checks belong (extend the existing bats/shellcheck jobs; no new pipeline)

## Inputs
- `.claude-plugin/marketplace.json` — existing entry shapes (guardrails inline-path entry is the model; NOT the dev-loop URL entry)
- `README.md` — plugin table + narrative to extend
- `.github/workflows/test.yml` — bats job (currently `bats plugins/guardrails/tests`) and shellcheck job (`plugins/guardrails/hooks/*.sh`)
- `plugins/memory-loop/.claude-plugin/plugin.json` (task 01) — description to mirror in the marketplace entry
- Decisions that bind you: D16 (version 0.1.0, entry mirrors guardrails' shape)

## Steps
1. `.claude-plugin/marketplace.json`: append a third `plugins[]` entry — name `memory-loop`, description from plugin.json (may shorten to one sentence), category `development`, same author block, `source: "./plugins/memory-loop"`, homepage the groundwork repo URL, version `0.1.0`, tags `["memory", "habits", "lifecycle", "identity", "self-improvement", "claude-code"]`.
2. Root `README.md`:
   - Plugin table: add row — **memory-loop** | "A memory lifecycle for your agent — a save gate against hallucinated memories, tiered expiry with archive-not-delete, a periodic learning-review nudge, a habit-distillation frame (HABITS.md), and an optional one-time identity setup (the assistant can even pick its own name)."
   - Install section: add `/plugin install memory-loop@groundwork`.
   - Narrative: where the intro presents the two plugins, present three axes — guardrails (safety) + dev-loop (quality) + memory-loop (continuity). Keep edits surgical; do not restructure unrelated sections.
3. `.github/workflows/test.yml`:
   - bats job: change the run step to `bats plugins/guardrails/tests plugins/memory-loop/tests` (or two lines).
   - shellcheck job: widen to `plugins/*/hooks/*.sh`.

## Deliverables
- `.claude-plugin/marketplace.json`
- `README.md`
- `.github/workflows/test.yml`

## Verify
- `jq . .claude-plugin/marketplace.json` → parses; `jq '.plugins | length'` → 3
- `bats plugins/guardrails/tests plugins/memory-loop/tests` → ALL pass (both plugins)
- `shellcheck -s bash plugins/*/hooks/*.sh` → clean
- Final hygiene sweep over everything new: grep `plugins/memory-loop` and `plans/memory-loop-v0.1` for the private org/user terms list kept outside this repo → 0 hits; Hangul scan over `plugins/memory-loop` → 0 hits

## Out of scope
- Publishing/launch posts; version bumps of other plugins; demo recordings
