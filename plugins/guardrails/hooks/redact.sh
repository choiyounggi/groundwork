#!/usr/bin/env bash
# groundwork / guardrails — shared secret redaction.
#
# Sourced by audit-log.sh (PostToolUse) and bash-guard.sh (escalation records)
# so the redaction regex lives in exactly ONE place. The source<->cache drift of
# this very regex once let tokens through; a single source prevents recurrence.
#
# bash 3.2 compatible.

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
