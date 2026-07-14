#!/usr/bin/env bash
# groundwork / memory-loop — Periodic learning-review nudge.
#
# Stop hook. Every N responses (default 10) it emits a learning-review
# reminder as {"decision":"block","reason":...} so the agent checks the recent
# stretch of work for habits, skills, and memories worth persisting; on every
# other response it stays silent. The reminder routes candidates through the
# save gate (the "remember" skill), so nothing lands in long-term memory
# unconfirmed.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/memory-loop.json          (global)
#     < <cwd>/.groundwork/memory-loop.json             (repo, team-shared)
# Key used here: "nudgeInterval" — fire every N responses (positive integer).
#
# Design notes (why it looks like this):
#   - stop_hook_active guard: when the Stop event is itself the product of a
#     previous block, exit immediately — prevents an infinite review loop.
#   - The block JSON is built with jq (no python dependency); "block" renders
#     as agent feedback, not as an error.
#   - State (the response counter) lives under ~/.claude/groundwork/memory-loop/,
#     never in /tmp.
#   - Fail open: unparsable input, config, or counter degrade to defaults.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || true)
[ "$ACTIVE" = "true" ] && exit 0

GLOBAL_CFG="${HOME}/.claude/groundwork/memory-loop.json"
REPO_CFG="${PWD}/.groundwork/memory-loop.json"

# nudgeInterval from the first config that defines it (repo > global).
INTERVAL=""
for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
  [ -f "$cfg" ] || continue
  v=$(jq -r '.nudgeInterval // empty' "$cfg" 2>/dev/null || true)
  if [ -n "$v" ]; then INTERVAL="$v"; break; fi
done
case "$INTERVAL" in
  ''|*[!0-9]*|0) INTERVAL=10 ;;
esac

STATE_DIR="${HOME}/.claude/groundwork/memory-loop"
COUNTER="${STATE_DIR}/nudge-counter"
mkdir -p "$STATE_DIR"

n=0
[ -f "$COUNTER" ] && n=$(cat "$COUNTER" 2>/dev/null || printf '0')
case "$n" in ''|*[!0-9]*) n=0 ;; esac
n=$((n + 1))

if [ "$n" -lt "$INTERVAL" ]; then
  printf '%s' "$n" > "$COUNTER"
  exit 0
fi

printf '0' > "$COUNTER"

REASON='Learning review (automatic nudge — several responses have passed).
Look back over the recent stretch of work for anything worth persisting:
  1. A repeated mistake, or a correction from the user  -> distill a habit into HABITS.md (memory-loop "habit" skill)
  2. A reusable procedure or pattern                    -> consider extracting a skill
  3. A fact future sessions will need                   -> save a memory (memory-loop "remember" skill)
Route every candidate through the save gate: confirm long/short tier with the user, and an expiry for short. Do not save unverified guesses.
If there is nothing worth persisting, say "Learning review: nothing to persist." and finish.'

jq -cn --arg r "$REASON" '{decision: "block", reason: $r}'
exit 0
