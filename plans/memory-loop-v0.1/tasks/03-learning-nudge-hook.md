# Task 03: learning-nudge.sh + bats tests

## Objective
A Stop hook that, every N responses (configurable, default 10), emits a
learning-review nudge as `{"decision":"block","reason":...}` and otherwise
stays silent. Loop-guarded via `stop_hook_active`.

## Wiki pages (read these first, only these)
- wiki/platforms/shells/portable-shell-scripts.md — quoting, `set -uo pipefail`, no-eval
- wiki/testing/quality/minimum-case-set.md — normal/error/boundary cases
- wiki/testing/quality/tests-that-cannot-fail.md — assert concrete JSON values; silence asserted explicitly

## Inputs
- `plugins/guardrails/hooks/bash-guard.sh` — header style, config lookup, jq patterns
- `plugins/guardrails/tests/bash-guard.bats` — bats conventions
- Decisions that bind you: D1, D5 (config precedence), D6 (state in `~/.claude/groundwork/memory-loop/nudge-counter`), D7 (jq-built block JSON; `stop_hook_active` guard; no python3)

## Steps
1. Write `plugins/memory-loop/hooks/learning-nudge.sh`:
   - Read stdin; `ACTIVE=$(... | jq -r '.stop_hook_active // false')`; `[ "$ACTIVE" = "true" ] && exit 0`.
   - `INTERVAL`: from config key `nudgeInterval` (repo > global, first hit wins), default `10`; validate it is a positive integer (`case` pattern), else fall back to 10.
   - State: `STATE_DIR="$HOME/.claude/groundwork/memory-loop"`; `mkdir -p`; read counter file, non-numeric → 0; increment.
   - If counter < INTERVAL: write counter back, exit 0 (no output).
   - Else: reset counter to 0 and print with `jq -cn --arg r "$REASON" '{decision:"block", reason:$r}'`. REASON (English, heredoc into a variable via `read -r -d '' || true` or `printf`):
     ```
     Learning review (automatic nudge — several responses have passed).
     Look back over the recent stretch of work for anything worth persisting:
       1. A repeated mistake, or a correction from the user  -> distill a habit into HABITS.md (memory-loop "habit" skill)
       2. A reusable procedure or pattern                    -> consider extracting a skill
       3. A fact future sessions will need                   -> save a memory (memory-loop "remember" skill)
     Route every candidate through the save gate: confirm long/short tier with the user, and an expiry for short. Do not save unverified guesses.
     If there is nothing worth persisting, say "Learning review: nothing to persist." and finish.
     ```
   - Always exit 0.
2. Write `plugins/memory-loop/tests/learning-nudge.bats` (helper: fake `HOME`, run hook with stdin built by `jq -cn`). Cases:
   - counter below interval: run once with default config → empty output, counter file contains `1`.
   - reaching interval: pre-seed counter to `9`, run → output parses as JSON with `.decision == "block"` and `.reason` containing `Learning review`; counter file reset to `0`.
   - custom interval: global config `{"nudgeInterval": 2}`, pre-seed counter `1` → fires.
   - `stop_hook_active: true` with counter pre-seeded at interval-1 → empty output AND counter unchanged (guard short-circuits before counting).
   - corrupt counter file (`abc`): run → treated as 0, becomes `1`, no output.
   - invalid config interval (`"nudgeInterval": "lots"`): falls back to 10 — pre-seed counter `9`, run → fires.

## Deliverables
- `plugins/memory-loop/hooks/learning-nudge.sh`
- `plugins/memory-loop/tests/learning-nudge.bats`

## Verify
- `bats plugins/memory-loop/tests/learning-nudge.bats` → all pass
- `shellcheck -s bash plugins/memory-loop/hooks/learning-nudge.sh` → clean

## Out of scope
- The habit/remember skills the nudge references (task 06)
