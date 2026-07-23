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

# Redact common secret shapes before persisting.
#   1-4: known token shapes (GitHub / AWS / Slack / OpenAI) — matched by form,
#        so they are caught even without a key name.
#   5:   Bearer tokens.
#   6:   `<cmd> configure set <...key...> VALUE` — space-separated secret args.
#   7:   key=value / key: value. The leading [A-Za-z0-9_-]* lets an env-var
#        prefix be absorbed (AWS_SECRET_ACCESS_KEY=...), while requiring a =/:
#        right after the keyword keeps column names like token_type / secret_level
#        (no =/: adjacent) readable — redaction favors precision over blanket masking.
# Case: BSD sed (macOS) has no case-insensitive flag, so key names carry explicit
# upper-case alternates (covers lower `password` and env-var `AWS_SECRET_ACCESS_KEY`).
redact() {
  printf '%s' "$1" | sed -E \
    -e 's/(gh[pousr]_)[A-Za-z0-9]{16,}/\1REDACTED/g' \
    -e 's/(AKIA|ASIA)[A-Z0-9]{8,}/\1REDACTED/g' \
    -e 's/(xox[baprs]-)[A-Za-z0-9-]{8,}/\1REDACTED/g' \
    -e 's/sk-[A-Za-z0-9]{16,}/sk-REDACTED/g' \
    -e 's/([Bb]earer[[:space:]]+)[A-Za-z0-9._-]{12,}/\1REDACTED/g' \
    -e 's/([Cc]onfigure[[:space:]]+set[[:space:]]+[A-Za-z0-9_.-]*([Ss]ecret|SECRET|[Tt]oken|TOKEN|[Pp]assword|PASSWORD|[Kk]ey|KEY)[A-Za-z0-9_.-]*[[:space:]]+)[^[:space:]]{4,}/\1REDACTED/g' \
    -e 's/([A-Za-z0-9_-]*([Pp]assword|PASSWORD|[Pp]asswd|PASSWD|[Tt]oken|TOKEN|[Ss]ecret|SECRET|[Cc]redential|CREDENTIAL|[Aa]uthorization|AUTHORIZATION|[Aa]pi[_-]?[Kk]ey|API[_-]?KEY|[Aa]ccess[_-]?[Kk]ey|ACCESS[_-]?KEY|[Pp]rivate[_-]?[Kk]ey|PRIVATE[_-]?KEY)[[:space:]]*[=:][[:space:]]*"?)[^[:space:]"'"'"']{6,}/\1REDACTED/g'
}
SUMMARY=$(redact "$SUMMARY")

# jq builds valid JSON (handles escaping); append one line.
jq -cn \
  --arg ts "$TS" --arg tool "$TOOL" --arg summary "$SUMMARY" \
  --arg cwd "$CWD" --argjson error "${IS_ERROR:-false}" \
  '{ts: $ts, tool: $tool, summary: $summary, error: $error, cwd: $cwd}' \
  >> "$LOG" 2>/dev/null || true

exit 0
