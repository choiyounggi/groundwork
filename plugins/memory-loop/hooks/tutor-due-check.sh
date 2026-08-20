#!/usr/bin/env bash
# groundwork / memory-loop — Tutor due-item reminder.
#
# SessionStart hook. Delegates counting to the tutor scheduler (t1's merged
# CLI); this hook never reimplements date or config logic — see
# skills/tutor/scripts/tutor-schedule.sh for the due/enable contract.
#
# Design notes (why it looks like this):
#   - Fail open everywhere: missing/failing scheduler, absent jq, malformed
#     stdin, non-numeric output all degrade to silent exit 0. A reminder
#     hook must never break session start, and stays a single quiet line —
#     no nagging, no counters (design doc: burnout insight #7).
#   - `due --count` already returns 0 when tutorEnabled=false, so this hook
#     does not duplicate the enable/disable check.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCHEDULER="$PLUGIN_ROOT/skills/tutor/scripts/tutor-schedule.sh"

[ -f "$SCHEDULER" ] || exit 0

COUNT=$(bash "$SCHEDULER" due --count 2>/dev/null || true)
case "$COUNT" in ''|*[!0-9]*) exit 0 ;; esac
[ "$COUNT" -gt 0 ] || exit 0

printf "memory-loop tutor: %s개 복습 항목이 대기 중 — '/memory-loop:tutor' 로 복습을 시작하세요.\\n" "$COUNT"
exit 0
