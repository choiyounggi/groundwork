#!/usr/bin/env bash
# groundwork / memory-loop — Correction-signal hook (UserPromptSubmit).
#
# When the user's prompt looks like a correction ("아니야", "그게 아니라",
# "틀렸어", "다시 해", "don't", "wrong"), this hook records a signal and adds
# one context line suggesting a habit or memory capture. It replaces the old
# Stop-hook nudge, which forced an extra model turn on a fixed interval: a
# UserPromptSubmit hook adds context to the turn that is already happening.
#
# Every match appends one line to ~/.claude/groundwork/memory-loop/signals.jsonl:
#     {"ts":"<UTC ISO-8601>","session_id":"<id>","matched":["<label>", ...]}
# Labels: 아니, 그게아니라, 틀렸, 다시해, dont, wrong.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/memory-loop.json          (global)
#     < <cwd>/.groundwork/memory-loop.json             (repo, team-shared)
# Keys used here:
#   "correctionInjectionCap" — max context injections per session. Default 3.
#                              0 disables injection; signals are still recorded.
#
# Design notes (why it looks like this):
#   - The prompt text is never written to disk — only the matched labels.
#   - All keywords are matched in one jq call (Oniguruma regex); "아니" needs a
#     boundary so 아니면/아니고/아니지 do not count. No Unicode normalization:
#     an NFD-encoded prompt silently fails to match (fail-open).
#   - Per-session counts live in correction-sessions/<session slug>, one file
#     per session so concurrent sessions never share a counter. After writing
#     its own file, every run prunes files idle for more than 2 days —
#     indiscriminately, so a session idle that long starts a fresh cap.
#   - Fail open: empty stdin, invalid JSON, or any parse failure exits 0 silently.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
# The UserPromptSubmit stdin field is `.prompt`, NOT `.user_prompt` —
# confirmed against code.claude.com/docs/en/hooks.md's own "UserPromptSubmit
# Input" JSON example (also mirrored at
# ~/.claude/plugins/cache/superpowers-marketplace/superpowers-developing-for-claude-code/0.3.1/skills/working-with-claude-code/references/hooks.md
# line ~305). `user_prompt` is a plugin-dev `test-hook.sh` fixture
# convention, not the real field name — do not "helpfully" switch this
# back after reading a generic hook-authoring reference.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
[ -n "$PROMPT" ] || exit 0
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

MATCHED_JSON=$(jq -cn --arg p "$PROMPT" '
$p as $x
| [
    (if ($x | test("아니(?=[,.!?…\\s]|$|야|요|다)")) then "아니" else empty end),
    (if ($x | test("그게\\s*아니라")) then "그게아니라" else empty end),
    (if ($x | test("틀렸")) then "틀렸" else empty end),
    (if ($x | test("다시\\s*해")) then "다시해" else empty end),
    (if ($x | test("\\bdon['"'"'\u2019]?t\\b"; "i")) then "dont" else empty end),
    (if ($x | test("\\bwrong\\b"; "i")) then "wrong" else empty end)
  ]
' 2>/dev/null || true)
[ -n "$MATCHED_JSON" ] || exit 0
MATCH_COUNT=$(printf '%s' "$MATCHED_JSON" | jq 'length' 2>/dev/null || printf '0')
case "$MATCH_COUNT" in ''|*[!0-9]*) exit 0 ;; esac
[ "$MATCH_COUNT" -gt 0 ] || exit 0

GLOBAL_CFG="${HOME}/.claude/groundwork/memory-loop.json"
REPO_CFG="${PWD}/.groundwork/memory-loop.json"

# Same body as habits-budget-guard.sh: repo config beats global beats fallback.
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
CAP=$(cfg_num correctionInjectionCap 3)

STATE_DIR="${HOME}/.claude/groundwork/memory-loop"
SESS_DIR="${STATE_DIR}/correction-sessions"
# No state dir means the cap cannot be enforced: record nothing, inject nothing.
mkdir -p "$SESS_DIR" 2>/dev/null || exit 0
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
# Braces so a failed redirection's own error is silenced too.
{ jq -cn --arg ts "$TS" --arg sid "$SESSION_ID" --argjson matched "$MATCHED_JSON" \
  '{ts:$ts, session_id:$sid, matched:$matched}' >> "${STATE_DIR}/signals.jsonl"; } 2>/dev/null || true

SLUG=$(printf '%s' "$SESSION_ID" | sed 's|[^a-zA-Z0-9]|-|g')
[ -n "$SLUG" ] || SLUG="unknown"
SESS_FILE="${SESS_DIR}/${SLUG}"
PRIOR=0
[ -f "$SESS_FILE" ] && PRIOR=$(cat "$SESS_FILE" 2>/dev/null || printf '0')
case "$PRIOR" in ''|*[!0-9]*) PRIOR=0 ;; esac
# An unwritten counter would leave PRIOR at 0 forever — never inject then.
{ printf '%s' "$((PRIOR + 1))" > "$SESS_FILE"; } 2>/dev/null || exit 0

# prune AFTER our own write (refreshes our mtime first) — indiscriminate,
# see the design notes above for the accepted cost
find "$SESS_DIR" -type f -mtime +2 -exec rm -f {} + 2>/dev/null || true

if [ "$CAP" -gt 0 ] 2>/dev/null && [ "$PRIOR" -lt "$CAP" ] 2>/dev/null; then
  CTX='Correction signal: that looked like a correction. If it points to a repeated mistake, consider capturing a habit (memory-loop "habit" skill) or saving a memory (memory-loop "remember" skill); otherwise continue.'
  jq -cn --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
fi
exit 0
