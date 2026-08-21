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
# Keys used here:
#   "nudgeInterval"        — fire every N responses (positive integer).
#   "habitsSplitWarnBytes" — when HABITS.md exceeds this, the nudge also asks
#                            for background prose to move to HABITS-CASES.md.
#                            0 disables the check. Default 40000.
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

# Numeric setting from the first config that defines it (repo > global),
# falling back to $2 when absent or not a non-negative integer.
cfg_num() {
  local key="$1" fallback="$2" cfg v=""
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    v=$(jq -r --arg k "$key" '.[$k] // empty' "$cfg" 2>/dev/null || true)
    if [ -n "$v" ]; then break; fi
  done
  case "$v" in
    ''|*[!0-9]*) printf '%s' "$fallback" ;;
    *) printf '%s' "$v" ;;
  esac
}

INTERVAL=$(cfg_num nudgeInterval 10)
[ "$INTERVAL" -gt 0 ] 2>/dev/null || INTERVAL=10

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

# HABITS.md is imported into every session, so it is re-read on every request —
# its size is paid per turn, not once. Background prose is what makes it grow,
# so past a threshold the nudge also asks for that prose to move out.
SPLIT_WARN=$(cfg_num habitsSplitWarnBytes 40000)
HABITS_FILE="${HOME}/.claude/groundwork/HABITS.md"
SPLIT_NOTE=""
if [ "$SPLIT_WARN" -gt 0 ] 2>/dev/null && [ -f "$HABITS_FILE" ]; then
  SZ=$(wc -c < "$HABITS_FILE" 2>/dev/null | tr -d ' ')
  case "$SZ" in ''|*[!0-9]*) SZ=0 ;; esac
  if [ "$SZ" -gt "$SPLIT_WARN" ]; then
    SPLIT_NOTE=$(printf '\n\nAlso: HABITS.md is %s bytes, past the %s-byte split threshold. It loads on every request, so background prose sitting there costs tokens on every turn. Move the (<- background: ...) text out of the 🟢 Practices entries into HABITS-CASES.md, leaving a [Cnn] pointer on each rule (the "habit" skill has the layout). Keep 🛑 hard lines inline — for a prohibition the origin is the judgment.' "$SZ" "$SPLIT_WARN")
  fi
fi

jq -cn --arg r "${REASON}${SPLIT_NOTE}" '{decision: "block", reason: $r}'
exit 0
