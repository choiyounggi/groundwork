#!/usr/bin/env bash
# remask-audit.sh — re-apply guardrails redaction to an EXISTING audit log whose
# lines were written before the redaction regex was fixed (finding: a stale
# plugin cache used an older redact() and leaked field values into the log).
#
# usage: remask-audit.sh [--apply] [logfile]
#   logfile  defaults to $GROUNDWORK_AUDIT_LOG or ~/.claude/groundwork/audit.jsonl
#   (no flag) DRY-RUN: report how many lines would change. No secrets are printed.
#   --apply   rewrite in place. Backs up to <log>.premask.bak first; chmod 600.
#
# Also processes rotated logs (<log>.*.old). Idempotent: an already-redacted line
# is left untouched. Never writes to /tmp — the work file is a sibling of the log.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || DIR="$(dirname "$0")"
# shellcheck source=/dev/null
. "$DIR/../hooks/redact.sh"

JQ=$(command -v jq) || { echo "remask-audit: jq not found" >&2; exit 127; }

apply=0
log="${GROUNDWORK_AUDIT_LOG:-$HOME/.claude/groundwork/audit.jsonl}"
for a in "$@"; do
  case "$a" in
    --apply) apply=1 ;;
    -*) echo "remask-audit: unknown option '$a'" >&2; exit 2 ;;
    *)  log="$a" ;;
  esac
done

remask_file() {  # $1 = path to a JSONL audit file
  local f="$1" tmp line summary red out total=0 changed=0
  [ -f "$f" ] || { echo "skip (not found): $f"; return 0; }
  [ -s "$f" ] || { echo "skip (empty):     $f"; return 0; }
  tmp="$f.remask.$$"
  : > "$tmp"
  while IFS= read -r line || [ -n "$line" ]; do
    total=$((total + 1))
    summary=$(printf '%s' "$line" | "$JQ" -r '.summary // empty' 2>/dev/null || echo "")
    if [ -z "$summary" ]; then printf '%s\n' "$line" >> "$tmp"; continue; fi
    red=$(redact "$summary")
    if [ "$red" != "$summary" ]; then
      changed=$((changed + 1))
      out=$(printf '%s' "$line" | "$JQ" -c --arg s "$red" '.summary=$s' 2>/dev/null) || out="$line"
      printf '%s\n' "$out" >> "$tmp"
    else
      printf '%s\n' "$line" >> "$tmp"
    fi
  done < "$f"
  echo "$f: $changed/$total line(s) would be re-masked"
  if [ "$apply" -eq 1 ] && [ "$changed" -gt 0 ]; then
    cp "$f" "$f.premask.bak" 2>/dev/null && chmod 600 "$f.premask.bak" 2>/dev/null || true
    mv "$tmp" "$f" 2>/dev/null && chmod 600 "$f" 2>/dev/null \
      || { echo "  ERROR: could not rewrite $f (left unchanged)" >&2; rm -f "$tmp"; return 0; }
    echo "  applied (backup: $f.premask.bak)"
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

remask_file "$log"
for old in "$log".*.old; do
  [ -f "$old" ] && remask_file "$old"
done

[ "$apply" -eq 1 ] || echo "(dry-run — re-run with --apply to rewrite)"
