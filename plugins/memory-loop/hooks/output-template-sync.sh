#!/usr/bin/env bash
# groundwork / memory-loop — Auto-merge the OUTPUT.md template on session start.
#
# SessionStart hook. `setup` seeds ~/.claude/groundwork/OUTPUT.md once and
# never overwrites it, because the file is the user's. That leaves a gap: a
# better template never reaches an existing install. This hook closes it by
# running scripts/sync-output-template.sh, which replaces only the managed
# block and leaves the user's own rules alone (backup written first).
#
# Quiet unless it changed something or could not. Never seeds the file: an
# OUTPUT.md nobody imported would be a silent no-op, so a missing file means
# "setup has not run" and the hook exits.
#
# Config (repo .groundwork/memory-loop.json overrides ~/.claude/groundwork/memory-loop.json):
#   "syncOutputTemplate" — false disables this hook. Default true.
#
# Output: at most one stdout line. Always exits 0 (fail open).
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

[ -n "${HOME:-}" ] || exit 0
TARGET="${HOME}/.claude/groundwork/OUTPUT.md"
[ -e "$TARGET" ] || exit 0

for cfg in "${CWD}/.groundwork/memory-loop.json" "${HOME}/.claude/groundwork/memory-loop.json"; do
  [ -f "$cfg" ] || continue
  if command -v jq >/dev/null 2>&1; then
    v=$(jq -r 'if has("syncOutputTemplate") then (.syncOutputTemplate | tostring) else empty end' "$cfg" 2>/dev/null || true)
  else
    v=$(grep -o '"syncOutputTemplate"[[:space:]]*:[[:space:]]*[a-z]*' "$cfg" 2>/dev/null | head -1 | sed 's/.*://; s/[[:space:]]//g')
  fi
  case "$v" in
    false) exit 0 ;;
    true)  break ;;
  esac
done

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
out=$(bash "${PLUGIN_ROOT}/scripts/sync-output-template.sh" "$TARGET" 2>&1)
rc=$?
first=$(printf '%s\n' "$out" | head -1)

case "$first" in
  ok:*) exit 0 ;;
esac
if [ "$rc" -ne 0 ]; then
  printf 'output style: template sync failed — %s\n' "$first"
  exit 0
fi
printf 'output style: %s\n' "$first"
exit 0
