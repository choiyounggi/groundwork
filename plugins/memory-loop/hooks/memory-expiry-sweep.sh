#!/usr/bin/env bash
# groundwork / memory-loop — Expiry sweep for short-tier memories.
#
# SessionStart hook. Moves memory files whose frontmatter says `tier: short`
# with an `expires: YYYY-MM-DD` date that has passed into that directory's
# archived/ subfolder — never deleting anything — and prints a report so the
# agent can tidy the memory index and offer promotions.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/memory-loop.json          (global)
#     < <cwd>/.groundwork/memory-loop.json             (repo, team-shared)
# Key used here: "extraMemoryDirs" — additional memory directories to sweep,
# on top of the project memory dir derived from the session cwd.
#
# Design notes (why it looks like this):
#   - Safe by default: files without `tier: short`, files with a conditional
#     `expires_when`, MEMORY.md, and anything unparsable are left untouched.
#     Pre-existing native memories carry no `tier` and are therefore immune.
#   - The expiry date is exclusive: a file expiring today is still live; it is
#     archived on the first session after the date has passed.
#   - Dates are compared as ISO strings (lexicographic == chronological), so
#     no BSD-vs-GNU `date` flag differences apply.
#   - Fail open: on any parse problem the hook stays silent and exits 0.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

GLOBAL_CFG="${HOME}/.claude/groundwork/memory-loop.json"
REPO_CFG="${CWD}/.groundwork/memory-loop.json"

# Project memory dir: Claude Code stores per-project memory under
# ~/.claude/projects/<slug>/memory, where <slug> is the cwd with every
# non-alphanumeric character replaced by "-".
SLUG=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9]|-|g')
DIRS=("${HOME}/.claude/projects/${SLUG}/memory")

# extraMemoryDirs from the first config that defines it (repo > global).
for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
  [ -f "$cfg" ] || continue
  extra=$(jq -r '.extraMemoryDirs[]?' "$cfg" 2>/dev/null || true)
  if [ -n "$extra" ]; then
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      DIRS+=("${d/#\~/$HOME}")
    done <<EOF
$extra
EOF
    break
  fi
done

TODAY=$(date +%Y-%m-%d)
count=0
report=""

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue

    # Frontmatter block only: between the leading --- pair.
    fm=$(awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f' "$f")

    tier=$(printf '%s\n' "$fm" \
           | sed -n 's/^[[:space:]]*tier:[[:space:]]*//p' \
           | tr -d "\"' " | head -1)
    [ "$tier" = "short" ] || continue

    exp=$(printf '%s\n' "$fm" \
          | sed -n 's/^[[:space:]]*expires:[[:space:]]*//p' \
          | tr -d "\"' " | head -1)
    [ -z "$exp" ] && continue

    # Absolute dates only; expires_when / anything else is a human decision.
    printf '%s' "$exp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || continue

    # ISO dates sort lexicographically; strictly-before-today == lapsed.
    if [[ "$exp" < "$TODAY" ]]; then
      mkdir -p "$dir/archived"
      if mv "$f" "$dir/archived/$base" 2>/dev/null; then
        count=$((count + 1))
        report="${report}  - ${base} (expired ${exp}, in ${dir})"$'\n'
      fi
    fi
  done
done

if [ "$count" -gt 0 ]; then
  printf 'Memory expiry sweep: %d short-tier memory file(s) moved to archived/ (not deleted).\n' "$count"
  printf '%s' "$report"
  printf 'Next: remove the corresponding index lines from that directory%ss MEMORY.md.\n' "'"
  printf 'If any archived fact is still valid, offer the user a promotion to tier: long (restore from archived/ and re-save through the save gate) — confirm with the user first.\n'
fi
exit 0
