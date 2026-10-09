#!/usr/bin/env bash
# groundwork / memory-loop — Keep the managed block of OUTPUT.md in step with
# the plugin's template.
#
# OUTPUT.md is the user's file. It has two parts: the user's own rules (above
# the managed block, never touched) and one managed block that mirrors
# templates/OUTPUT.md. The block's opening marker carries a template id (a
# cksum of the block body), so a changed template is detected by content, not
# by a version number anyone has to remember to bump.
#
#   target missing               -> created from the whole template
#   block present, same id       -> "ok:" and no write
#   block present, other id      -> block replaced, everything else kept
#   no block, file is an untouched
#     pre-2.3.0 seed             -> whole file replaced (it was our text anyway)
#   no block, anything else      -> the user's file kept, block appended
#   open marker, no close        -> error, file untouched
#
# Marker lines inside a ``` code fence are the user's prose (someone quoting
# the syntax) and are never treated as the block. A backup is written next to
# the file before any change. Symlinks are followed so a dotfiles link
# survives; a dangling link is an error, never replaced. The file's mode is
# kept.
#
# Usage: sync-output-template.sh [target]   (default: $HOME/.claude/groundwork/OUTPUT.md)
# Env:   CLAUDE_PLUGIN_ROOT (plugin dir; default: this script's parent)
#        OUTPUT_TEMPLATE    (template path; default: $CLAUDE_PLUGIN_ROOT/templates/OUTPUT.md)
# Exit:  0 written or nothing to do; 1 on any failure (the target is then untouched).
# Stdout: exactly one line — created: | ok: | merged: | replaced: | updated:
# bash 3.2 compatible.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${BASH_SOURCE[0]%/scripts/*}}"
TEMPLATE="${OUTPUT_TEMPLATE:-${PLUGIN_ROOT}/templates/OUTPUT.md}"
OPEN_PREFIX='<!-- groundwork:memory-loop output-style'
CLOSE='<!-- /groundwork:memory-loop output-style -->'
# cksums of the block-less templates shipped before 2.3.0 (2.1.0, 2.2.0). A
# file that still matches one was seeded by setup and never edited, so it is
# replaced whole instead of having its own text duplicated by the block.
OLD_SEEDS="4218230957 3125880334"

die() { echo "sync-output-template: $*" >&2; exit 1; }

if [ $# -ge 1 ]; then
  TARGET="$1"
else
  [ -n "${HOME:-}" ] || die "HOME is not set and no target was given"
  TARGET="${HOME}/.claude/groundwork/OUTPUT.md"
fi

[ -f "$TEMPLATE" ] || die "template not found: $TEMPLATE"

VERSION=$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1)
[ -n "$VERSION" ] || VERSION="unknown"

# Line numbers of the first opening marker and the first closing marker after
# it, ignoring anything inside a ``` fence. CR-tolerant. Prints "open close"
# (either may be empty).
find_markers() {
  tr -d '\r' < "$1" | awk -v o="$OPEN_PREFIX" -v c="$CLOSE" '
    /^```/ { fence = !fence; next }
    fence { next }
    !ol && index($0, o) == 1 { ol = NR; next }
    ol && !cl && $0 == c { cl = NR }
    END { printf "%s %s\n", ol, cl }'
}

# The template's header (everything before the opening marker) and block body
# (strictly between the markers). Both markers must be there.
markers=$(find_markers "$TEMPLATE")
T_OPEN="${markers%% *}"; T_CLOSE="${markers#* }"
[ -n "$T_OPEN" ] || die "template has no opening marker: $TEMPLATE"
[ -n "$T_CLOSE" ] || die "template has no closing marker: $TEMPLATE"
HEADER=$(tr -d '\r' < "$TEMPLATE" | awk -v n="$T_OPEN" 'NR < n')
BODY=$(tr -d '\r' < "$TEMPLATE" | awk -v a="$T_OPEN" -v b="$T_CLOSE" 'NR > a && NR < b')
[ -n "$BODY" ] || die "template has an empty managed block: $TEMPLATE"

ID=$(printf '%s\n' "$BODY" | cksum | cut -d' ' -f1)
OPEN="${OPEN_PREFIX} — managed block, template ${ID} (memory-loop ${VERSION}); your own rules go ABOVE this line and survive upgrades; this block is replaced on upgrade -->"

write_block() {
  printf '%s\n' "$OPEN"
  printf '%s\n' "$BODY"
  printf '%s\n' "$CLOSE"
}
write_whole() {
  [ -z "$HEADER" ] || printf '%s\n\n' "$HEADER"
  write_block
}

# Follow a symlink (dotfiles setups) so the real file is edited and the link
# survives. A dangling link is an error: replacing it would orphan the link.
hops=0
while [ -L "$TARGET" ]; do
  hops=$((hops + 1))
  [ "$hops" -le 32 ] || die "symlink loop at $TARGET"
  link=$(readlink "$TARGET") || die "cannot read symlink $TARGET"
  case $link in
    /*) TARGET=$link ;;
    *)  TARGET="$(dirname "$TARGET")/$link" ;;
  esac
  [ -e "$TARGET" ] || die "dangling symlink: $TARGET does not exist — create it (or fix the link), then re-run"
done

# --- no target yet: seed it from the whole template ---
if [ ! -e "$TARGET" ]; then
  mkdir -p "$(dirname "$TARGET")" || die "cannot create $(dirname "$TARGET")"
  NEW="${TARGET}.tmp.$$"
  trap 'rm -f "$NEW"' EXIT INT TERM
  write_whole > "$NEW" || die "cannot write $NEW"
  mv "$NEW" "$TARGET" || die "cannot create $TARGET"
  trap - EXIT
  printf 'created: %s (template %s, memory-loop %s)\n' "$TARGET" "$ID" "$VERSION"
  exit 0
fi

[ -d "$TARGET" ] && die "$TARGET is a directory"
[ -f "$TARGET" ] || die "$TARGET is not a regular file"

markers=$(find_markers "$TARGET")
open_line="${markers%% *}"; close_line="${markers#* }"

if [ -n "$open_line" ] && [ -z "$close_line" ]; then
  die "found the opening marker but no closing marker in $TARGET — restore the line '$CLOSE' after the block, or delete the block, then re-run"
fi

OLD_ID=""
if [ -n "$open_line" ]; then
  OLD_ID=$(tr -d '\r' < "$TARGET" | sed -n "${open_line}p" | sed -n 's/.* template \([0-9][0-9]*\) .*/\1/p')
  if [ "$OLD_ID" = "$ID" ]; then
    printf 'ok: %s is current (template %s)\n' "$TARGET" "$ID"
    exit 0
  fi
fi

NEW="${TARGET}.tmp.$$"
trap 'rm -f "$NEW"' EXIT INT TERM
# cp -p keeps the target's mode (e.g. 600) on the file that will replace it.
cp -p "$TARGET" "$NEW" || die "cannot write next to $TARGET"

if [ -n "$open_line" ]; then
  # Replace the block in place; the user's lines above and below are copied
  # unchanged (CRLF endings kept).
  n=0
  while IFS= read -r l || [ -n "$l" ]; do
    n=$((n + 1))
    if [ "$n" -lt "$open_line" ] || [ "$n" -gt "$close_line" ]; then
      printf '%s\n' "$l"
    elif [ "$n" -eq "$open_line" ]; then
      write_block
    fi
  done < "$TARGET" > "$NEW"
  ok=$?
  what="updated: $TARGET template ${OLD_ID:-?} -> $ID (memory-loop $VERSION)"
else
  file_sum=$(cksum < "$TARGET" | cut -d' ' -f1)
  case " $OLD_SEEDS " in
    *" $file_sum "*)
      write_whole > "$NEW"
      ok=$?
      what="replaced: $TARGET was an unedited pre-2.3.0 seed, now template $ID (memory-loop $VERSION)" ;;
    *)
      {
        cat "$TARGET" &&
        # ($(...) strips a trailing newline, so a non-empty result means none was there.)
        { [ ! -s "$TARGET" ] || [ -z "$(tail -c 1 "$TARGET")" ] || printf '\n'; } &&
        { [ ! -s "$TARGET" ] || printf '\n'; } &&
        write_block
      } > "$NEW"
      ok=$?
      what="merged: $TARGET kept, template $ID (memory-loop $VERSION) appended" ;;
  esac
fi
[ "$ok" -eq 0 ] || die "could not build the new file (disk full or permission denied?); $TARGET is untouched"
grep -qxF -- "$CLOSE" "$NEW" || die "new file is missing the closing marker (short write?); $TARGET is untouched"

BACKUP=""
if [ -s "$TARGET" ]; then
  BACKUP="${TARGET}.bak-$(date +%Y%m%d%H%M%S).$$"
  cp -p "$TARGET" "$BACKUP" || die "backup failed: $BACKUP"
fi

mv "$NEW" "$TARGET" || die "cannot replace $TARGET (backup: ${BACKUP:-none})"
trap - EXIT

printf '%s (backup: %s)\n' "$what" "${BACKUP:-none, file was empty}"
exit 0
