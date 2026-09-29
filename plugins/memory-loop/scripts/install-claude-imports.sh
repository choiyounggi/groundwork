#!/usr/bin/env bash
# groundwork / memory-loop — Ensure the plugin's @imports are in ~/.claude/CLAUDE.md.
#
# Run by the `setup` skill. Idempotent: every import line that is already
# present anywhere in the file (as a whole line — a copy inside a code fence
# counts too, so tell the user) is left alone; the rest are added inside one
# managed block, appended at the end or, if the block already exists, inserted
# before its closing marker. A backup is written next to the file before any
# change. The user's own lines are copied byte-for-byte (CRLF endings kept).
#
# Usage: install-claude-imports.sh            (target: $HOME/.claude/CLAUDE.md)
# Exit:  0 written or nothing to do; 1 on any failure (the file is then untouched).
# bash 3.2 compatible.
set -uo pipefail

TARGET="${HOME}/.claude/CLAUDE.md"
IMPORTS="@groundwork/HABITS.md
@groundwork/OUTPUT.md"
OPEN='<!-- groundwork:memory-loop imports — managed by /memory-loop:setup; edit the files, not these lines -->'
CLOSE='<!-- /groundwork:memory-loop -->'

die() { echo "install-claude-imports: $*" >&2; exit 1; }

mkdir -p "$(dirname "$TARGET")" || die "cannot create $(dirname "$TARGET")"
[ -d "$TARGET" ] && die "$TARGET is a directory"
[ -e "$TARGET" ] || : > "$TARGET" || die "cannot create $TARGET"

# Follow a symlink (dotfiles setups) so the real file is edited and the link
# survives. `readlink -f` is not available on macOS bash 3.2 systems.
while [ -L "$TARGET" ]; do
  link=$(readlink "$TARGET") || die "cannot read symlink $TARGET"
  case $link in
    /*) TARGET=$link ;;
    *)  TARGET="$(dirname "$TARGET")/$link" ;;
  esac
done
[ -f "$TARGET" ] || die "$TARGET is not a regular file"

# Whole-line presence check, tolerant of CRLF endings.
has_line() { tr -d '\r' < "$TARGET" | grep -qxF -- "$1"; }

MISSING=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  has_line "$line" || MISSING="${MISSING}${line}
"
done <<EOF_IMPORTS
$IMPORTS
EOF_IMPORTS

if [ -z "$MISSING" ]; then
  echo "ok: all memory-loop imports already present in $TARGET"
  exit 0
fi

if has_line "$OPEN" && ! has_line "$CLOSE"; then
  die "found the opening marker but no closing marker in $TARGET — restore the line '$CLOSE' after the block, or delete the block, then re-run"
fi

NEW="${TARGET}.tmp.$$"
trap 'rm -f "$NEW"' EXIT INT TERM
# cp -p keeps the target's mode (e.g. 600) on the file that will replace it.
cp -p "$TARGET" "$NEW" || die "cannot write next to $TARGET"

if has_line "$CLOSE"; then
  # Insert the missing lines just before the closing marker of the existing
  # block. (Plain bash, not awk: BSD awk rejects a -v value with newlines.)
  inserted=""
  while IFS= read -r l || [ -n "$l" ]; do
    if [ -z "$inserted" ] && [ "${l%$'\r'}" = "$CLOSE" ]; then
      printf '%s' "$MISSING"
      inserted=1
    fi
    printf '%s\n' "$l"
  done < "$TARGET" > "$NEW"
  ok=$?
else
  {
    cat "$TARGET" &&
    # ($(...) strips a trailing newline, so a non-empty result means none was there.)
    { [ ! -s "$TARGET" ] || [ -z "$(tail -c 1 "$TARGET")" ] || printf '\n'; } &&
    { [ ! -s "$TARGET" ] || printf '\n'; } &&
    printf '%s\n' "$OPEN" &&
    printf '%s' "$MISSING" &&
    printf '%s\n' "$CLOSE"
  } > "$NEW"
  ok=$?
fi
[ "$ok" -eq 0 ] || die "could not build the new file (disk full?); $TARGET is untouched"
# Both paths only add bytes: a smaller result means a short write.
[ "$(wc -c < "$NEW")" -gt "$(wc -c < "$TARGET")" ] || die "new file is not larger than the original; $TARGET is untouched"

BACKUP=""
if [ -s "$TARGET" ]; then
  BACKUP="${TARGET}.bak-$(date +%Y%m%d%H%M%S).$$"
  cp -p "$TARGET" "$BACKUP" || die "backup failed: $BACKUP"
fi

mv "$NEW" "$TARGET" || die "cannot replace $TARGET (backup: ${BACKUP:-none})"
trap - EXIT

printf 'added to %s (backup: %s):\n' "$TARGET" "${BACKUP:-none, file was empty}"
printf '%s' "$MISSING"
exit 0
