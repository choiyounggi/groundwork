#!/usr/bin/env bash
# groundwork / memory-loop — HABITS.md budget guard.
#
# PreToolUse(Edit|Write) hook. The habit file is imported into every session,
# so it is re-read on every request: its size is paid per turn, multiplied by
# the length of the conversation. A capture loop with no cap grows it forever,
# because every session has something that "feels worth keeping" and no session
# is the one that removes anything.
#
# This guard puts the cap where it can actually bind — at the write. A write
# that pushes the habit file past its budget is denied; a write that SHRINKS it
# is always allowed, so the way out of an over-budget file is never blocked.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/memory-loop.json          (global)
#     < <cwd>/.groundwork/memory-loop.json             (repo, team-shared)
# Keys used here:
#   "habitsBudgetBytes"  — max size of the always-loaded habit file. 0 disables.
#                          Default 8000 (~2k tokens on every request). The rule
#                          count is the tighter constraint in practice; this is
#                          the backstop against rules that grow into essays.
#   "habitsMaxRules"     — max number of rules in the file (🟢 and 🛑 alike).
#                          0 disables. Default 24.
#   "habitsPath"         — the habit file to guard ("~" expanded).
#                          Default ~/.claude/groundwork/HABITS.md
#
# Design notes (why it looks like this):
#   - Growth-only denial: the prospective size is compared to the budget, but a
#     write is denied only when it also makes the file BIGGER. Consolidation,
#     merges and archiving must stay possible at any size — a guard that locks
#     the file in its over-budget state would be worse than no guard.
#   - Rule counting is done on the DELTA (occurrences added minus removed in
#     the replaced span), never by parsing the whole document, so it does not
#     depend on section markers surviving an edit. That is also why the cap is
#     over ALL rules rather than the 🟢 section alone: an edit's span cannot be
#     located in a section without applying the edit first. A 🛑 hard line that
#     genuinely deserves a slot gets one by naming the rule it replaces.
#   - Edit size math is `current - len(old_string) + len(new_string)`. With
#     replace_all it under-counts, which can only make the guard more
#     permissive — it never invents a denial.
#   - Fail open: unreadable input, missing jq, a path that is not the habit
#     file, or any parse failure exits silently with no decision.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

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

# Path setting from the first config that defines it, with ~ expansion (same
# convention as extraMemoryDirs). Falls back to $2 when unset.
cfg_path() {
  local key="$1" fallback="$2" cfg v=""
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    v=$(jq -r --arg k "$key" '.[$k] // empty' "$cfg" 2>/dev/null || true)
    if [ -n "$v" ]; then break; fi
  done
  [ -n "$v" ] || v="$fallback"
  # shellcheck disable=SC2088  # the "~" here are literal prefix patterns; the
  # branches do the expansion with $HOME themselves.
  case "$v" in
    '~') v="$HOME" ;;
    '~/'*) v="${HOME}/${v:2}" ;;
  esac
  printf '%s' "$v"
}

HABITS_FILE=$(cfg_path habitsPath "${HOME}/.claude/groundwork/HABITS.md")
TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[ -n "$TARGET" ] || exit 0
[ "$TARGET" = "$HABITS_FILE" ] || exit 0

BUDGET=$(cfg_num habitsBudgetBytes 8000)
MAX_RULES=$(cfg_num habitsMaxRules 24)
# Both checks disabled — nothing to do.
[ "$BUDGET" -eq 0 ] 2>/dev/null && [ "$MAX_RULES" -eq 0 ] 2>/dev/null && exit 0

CUR_BYTES=0
CUR_RULES=0
if [ -f "$HABITS_FILE" ]; then
  CUR_BYTES=$(wc -c < "$HABITS_FILE" 2>/dev/null | tr -d ' ')
  case "$CUR_BYTES" in ''|*[!0-9]*) CUR_BYTES=0 ;; esac
  CUR_RULES=$(grep -c '^- \*\*' "$HABITS_FILE" 2>/dev/null | tr -d ' ')
  case "$CUR_RULES" in ''|*[!0-9]*) CUR_RULES=0 ;; esac
fi

# Bytes and rule-starts in a string handed to us by the tool call. `jq -j`
# writes the raw value with no trailing newline, so wc -c is the exact length.
str_bytes() {
  printf '%s' "$INPUT" | jq -j --arg k "$1" '.tool_input[$k] // ""' 2>/dev/null | wc -c | tr -d ' '
}
str_rules() {
  printf '%s' "$INPUT" | jq -j --arg k "$1" '.tool_input[$k] // ""' 2>/dev/null \
    | grep -c '^- \*\*' 2>/dev/null | tr -d ' '
}

if [ "$TOOL" = "Write" ]; then
  NEW_BYTES=$(str_bytes content)
  NEW_RULES=$(str_rules content)
else
  OLD_LEN=$(str_bytes old_string)
  NEW_LEN=$(str_bytes new_string)
  OLD_RULES=$(str_rules old_string)
  NEW_RULES_IN=$(str_rules new_string)
  NEW_BYTES=$((CUR_BYTES - OLD_LEN + NEW_LEN))
  NEW_RULES=$((CUR_RULES - OLD_RULES + NEW_RULES_IN))
fi
case "$NEW_BYTES" in ''|*[!0-9]*) exit 0 ;; esac
case "$NEW_RULES" in ''|*[!0-9]*) exit 0 ;; esac

deny() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

NAME=$(basename "$HABITS_FILE")
ADVICE=$(printf 'Do not add a rule until it is back under budget. Either (a) merge the new lesson into an existing rule with an overlapping trigger, (b) move rules that fail the recurrence or generality gate out to HABITS-ARCHIVE.md beside %s, or (c) name the existing rule this one replaces and remove it in the same edit. A write that shrinks %s is always allowed.' "$NAME" "$NAME")

if [ "$BUDGET" -gt 0 ] 2>/dev/null \
   && [ "$NEW_BYTES" -gt "$BUDGET" ] && [ "$NEW_BYTES" -gt "$CUR_BYTES" ]; then
  deny "$(printf '%s is budgeted at %s bytes; this write would make it %s (now %s). It is imported into every session, so every byte is re-read on every request. %s' \
    "$NAME" "$BUDGET" "$NEW_BYTES" "$CUR_BYTES" "$ADVICE")"
fi

if [ "$MAX_RULES" -gt 0 ] 2>/dev/null \
   && [ "$NEW_RULES" -gt "$MAX_RULES" ] && [ "$NEW_RULES" -gt "$CUR_RULES" ]; then
  deny "$(printf '%s is capped at %s rules; this write would make it %s (now %s). The list stops working as a list once it is too long to scan. %s' \
    "$NAME" "$MAX_RULES" "$NEW_RULES" "$CUR_RULES" "$ADVICE")"
fi

exit 0
