#!/usr/bin/env bash
# groundwork / guardrails — redacted audit log.
#
# PostToolUse hook. Appends a one-line JSON record of Bash + MCP tool calls to
#   ~/.claude/groundwork/audit.jsonl   (override with $GROUNDWORK_AUDIT_LOG)
# Secrets in the command are redacted before writing. The log is chmod 600 and
# rotates at 10 MB. This hook must NEVER fail — a broken audit must not block work.
#
# bash 3.2 compatible; BSD/GNU stat + date fallbacks.
set -uo pipefail

LOG="${GROUNDWORK_AUDIT_LOG:-${HOME}/.claude/groundwork/audit.jsonl}"
DIR=$(dirname "$LOG")
mkdir -p "$DIR" 2>/dev/null || true

if [ ! -f "$LOG" ]; then
  touch "$LOG" 2>/dev/null || exit 0
  chmod 600 "$LOG" 2>/dev/null || true
fi

# Rotate at 10 MB (BSD: stat -f%z, GNU: stat -c%s).
MAX=$((10 * 1024 * 1024))
SIZE=$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)
if [ "${SIZE:-0}" -gt "$MAX" ] 2>/dev/null; then
  mv "$LOG" "${LOG}.$(date +%Y%m%d%H%M%S 2>/dev/null || echo old).old" 2>/dev/null || true
  touch "$LOG" 2>/dev/null || true
  chmod 600 "$LOG" 2>/dev/null || true
fi

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
IS_ERROR=$(printf '%s' "$INPUT" | jq -r '.tool_response.isError // false' 2>/dev/null)
case "$IS_ERROR" in true|false) : ;; *) IS_ERROR=false ;; esac

# Summary: the Bash command, else a compact of tool_input (for MCP tools).
SUMMARY=$(printf '%s' "$INPUT" \
  | jq -r '.tool_input.command // (.tool_input | tojson) // empty' 2>/dev/null \
  | head -c 300 | tr '\n' ' ')

# Redact secrets before persisting — shared logic in redact.sh (single source,
# also used by the escalation path in bash-guard.sh).
# shellcheck source=/dev/null
. "$(dirname "$0")/redact.sh"
SUMMARY=$(redact "$SUMMARY")

# jq builds valid JSON (handles escaping); append one line.
jq -cn \
  --arg ts "$TS" --arg tool "$TOOL" --arg summary "$SUMMARY" \
  --arg cwd "$CWD" --argjson error "${IS_ERROR:-false}" \
  '{ts: $ts, tool: $tool, summary: $summary, error: $error, cwd: $cwd}' \
  >> "$LOG" 2>/dev/null || true

exit 0
