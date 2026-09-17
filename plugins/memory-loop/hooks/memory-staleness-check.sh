#!/usr/bin/env bash
# groundwork / memory-loop — Memory upkeep check.
#
# SessionStart hook. Capture, expiry and consolidation all exist, but only
# consolidation keeps memory *coherent* and it has no trigger — it is a manual
# skill nobody remembers to run. So the index drifts from the files, a fact
# that was true in March sits unchallenged in September, and the only thing
# that ever notices is a session that happens to trip over it.
#
# This hook is that trigger. It reports — it never writes: every repair goes
# through the consolidate/remember confirmation gates. It also stays quiet
# unless something actually fires, and then goes quiet again for a cooldown
# period, because a reminder that prints every session becomes wallpaper.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/memory-loop.json          (global)
#     < <cwd>/.groundwork/memory-loop.json             (repo, team-shared)
# Keys used here:
#   "memoryReviewDays"        — a memory untouched for this many days becomes a
#                               re-verification candidate. 0 disables. Default 90.
#   "memoryIndexMaxLines"     — MEMORY.md line count that calls for a
#                               consolidation pass. 0 disables. Default 120.
#   "consolidateIntervalDays" — nag when the last recorded consolidate run is
#                               older than this. 0 disables. Default 30.
#   "memoryCheckCooldownDays" — stay silent for this long after reporting.
#                               0 reports every session. Default 7.
#   "extraMemoryDirs"         — extra memory dirs, same as the expiry sweep.
#
# Design notes (why it looks like this):
#   - "Last touched" is the LATER of frontmatter `reviewed:` and `modified:`,
#     then the file's mtime. `reviewed:` exists so that confirming a memory is
#     still true costs one line instead of faking a content change; taking
#     whichever field appears first instead of the later date would flag a file
#     edited after its last review (consolidate's own "partly wrong -> correct
#     it, set modified" step never touches `reviewed`).
#   - Buckets follow consolidate's own scope contract, three ways: `tier: long`
#     (consolidate may act), `tier: short` without an absolute `expires:`
#     (nothing archives those, so only the event can retire them), and untiered
#     (consolidate is forbidden to touch them — they go through the `remember`
#     save gate, which is what assigns a tier). A short memory WITH an absolute
#     expiry is the expiry sweep's business and is never mentioned here.
#   - Index references are extracted as exact filenames. A substring test would
#     let an index line for `oauth.md` hide an orphaned `auth.md`.
#   - All date comparisons are ISO string compares against one precomputed
#     cutoff, so no BSD-vs-GNU date arithmetic appears in the loop.
#   - Fail open: no jq, no dirs, unparsable dates or config all exit 0 silently.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$CWD" ] && CWD="$PWD"

GLOBAL_CFG="${HOME}/.claude/groundwork/memory-loop.json"
REPO_CFG="${CWD}/.groundwork/memory-loop.json"
STATE_DIR="${HOME}/.claude/groundwork/memory-loop"

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

REVIEW_DAYS=$(cfg_num memoryReviewDays 90)
MAX_LINES=$(cfg_num memoryIndexMaxLines 120)
INTERVAL_DAYS=$(cfg_num consolidateIntervalDays 30)
COOLDOWN=$(cfg_num memoryCheckCooldownDays 7)

TODAY=$(date +%Y-%m-%d 2>/dev/null || true)
[ -n "$TODAY" ] || exit 0

# today - $1 days, as YYYY-MM-DD. BSD first, then GNU. Empty on failure.
days_ago() {
  date -v-"$1"d +%Y-%m-%d 2>/dev/null && return 0
  date -d "$1 days ago" +%Y-%m-%d 2>/dev/null && return 0
  printf ''
}

# The file's mtime as YYYY-MM-DD (GNU date -r, then BSD stat). Empty on failure.
mtime_date() {
  local v
  v=$(date -r "$1" +%Y-%m-%d 2>/dev/null || stat -f %Sm -t %Y-%m-%d "$1" 2>/dev/null || true)
  case "$v" in ????-??-??) printf '%s' "$v" ;; *) printf '' ;; esac
}

# Cooldown: stay silent unless the last report is older than the cooldown.
LAST_REPORT_FILE="${STATE_DIR}/staleness-last-report"
if [ "$COOLDOWN" -gt 0 ] 2>/dev/null && [ -f "$LAST_REPORT_FILE" ]; then
  last=$(cat "$LAST_REPORT_FILE" 2>/dev/null || true)
  cool_cut=$(days_ago "$COOLDOWN")
  case "$last" in
    ????-??-??) [ -n "$cool_cut" ] && [ ! "$last" \< "$cool_cut" ] && exit 0 ;;
  esac
fi

SLUG=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9]|-|g')
DIRS=("${HOME}/.claude/projects/${SLUG}/memory")
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

REVIEW_CUT=""
[ "$REVIEW_DAYS" -gt 0 ] 2>/dev/null && REVIEW_CUT=$(days_ago "$REVIEW_DAYS")

# The frontmatter block only: between the leading --- pair.
frontmatter() {
  awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f' "$1" 2>/dev/null || true
}

# One YYYY-MM-DD frontmatter field ($1) out of a frontmatter block ($2).
fm_date() {
  local v
  v=$(printf '%s\n' "$2" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | tr -d "\"'" | cut -c1-10 | head -1)
  case "$v" in ????-??-??) printf '%s' "$v" ;; *) printf '' ;; esac
}

# Last time a memory file was meaningfully touched: the LATER of `reviewed` and
# `modified`, falling back to the file's mtime when neither parses.
last_touch() {
  local f="$1" fm r m
  fm=$(frontmatter "$f")
  r=$(fm_date reviewed "$fm")
  m=$(fm_date modified "$fm")
  if [ -n "$r" ] && [ -n "$m" ]; then
    if [ "$r" \< "$m" ]; then printf '%s' "$m"; else printf '%s' "$r"; fi
    return 0
  fi
  [ -n "$r" ] && { printf '%s' "$r"; return 0; }
  [ -n "$m" ] && { printf '%s' "$m"; return 0; }
  mtime_date "$f"
}

stale_long=""        # tier: long — consolidate may act on these
stale_conditional="" # tier: short with no absolute expiry — nothing archives these
stale_untiered=""    # no tier — must go through the remember gate
broken=""
orphan=""
drift=0
index_lines_over=""

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || continue
  index="$dir/MEMORY.md"
  index_body=""
  index_refs=""
  if [ -f "$index" ]; then
    index_body=$(cat "$index" 2>/dev/null || true)
    index_refs=$(printf '%s\n' "$index_body" | grep -o '([^()]*\.md)' 2>/dev/null \
                 | sed 's/^(//; s/)$//' | sort -u)
  fi

  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue

    if [ -n "$index_body" ] && ! printf '%s\n' "$index_refs" | grep -qxF "$base"; then
      orphan="${orphan}${base} "
    fi

    if [ -n "$REVIEW_CUT" ]; then
      touched=$(last_touch "$f")
      if [ -n "$touched" ] && [ "$touched" \< "$REVIEW_CUT" ]; then
        fm=$(frontmatter "$f")
        tier=$(printf '%s\n' "$fm" | sed -n 's/^[[:space:]]*tier:[[:space:]]*//p' | tr -d "\"'" | head -1)
        case "$tier" in
          long)
            stale_long="${stale_long}${base}(${touched}) " ;;
          short)
            # An absolute `expires:` belongs to the expiry sweep — say nothing.
            # A conditional or missing one is archived by nothing at all, so a
            # short memory can outlive its event in silence.
            if [ -z "$(fm_date expires "$fm")" ]; then
              stale_conditional="${stale_conditional}${base}(${touched}) "
            fi ;;
          *)
            stale_untiered="${stale_untiered}${base}(${touched}) " ;;
        esac
      fi
    fi
  done

  [ -f "$index" ] || continue

  # Index entries pointing at files that are not there.
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    [ -e "$dir/$ref" ] || broken="${broken}${ref} "
  done <<EOF
$index_refs
EOF

  # Index older than a memory file: its one-line summary may no longer describe
  # what that file now says. This is the drift that bit us in practice.
  idx_date=$(mtime_date "$index")
  if [ -n "$idx_date" ]; then
    for f in "$dir"/*.md; do
      [ -e "$f" ] || continue
      [ "$(basename "$f")" = "MEMORY.md" ] && continue
      fd=$(mtime_date "$f")
      [ -n "$fd" ] || continue
      if [ "$idx_date" \< "$fd" ]; then drift=$((drift + 1)); fi
    done
  fi

  if [ "$MAX_LINES" -gt 0 ] 2>/dev/null; then
    n=$(grep -c '' "$index" 2>/dev/null | tr -d ' ')
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    [ "$n" -gt "$MAX_LINES" ] && index_lines_over="${n}/${MAX_LINES}"
  fi
done

# Last recorded consolidate run (the skill writes this when it finishes).
overdue=""
if [ "$INTERVAL_DAYS" -gt 0 ] 2>/dev/null; then
  cut=$(days_ago "$INTERVAL_DAYS")
  lastc=""
  [ -f "${STATE_DIR}/last-consolidate" ] && lastc=$(cat "${STATE_DIR}/last-consolidate" 2>/dev/null || true)
  case "$lastc" in
    ????-??-??) [ -n "$cut" ] && [ "$lastc" \< "$cut" ] && overdue="last run $lastc" ;;
    *) overdue="never run" ;;
  esac
fi

[ -z "$stale_long$stale_conditional$stale_untiered$broken$orphan$index_lines_over$overdue" ] \
  && [ "$drift" -eq 0 ] && exit 0

printf 'memory upkeep — the consolidate pass has no automatic trigger, so here is what it would look at:\n'
[ -n "$stale_long" ] && printf '  - re-verify (%s+ days untouched, tier: long — consolidate may act): %s\n' "$REVIEW_DAYS" "$stale_long"
[ -n "$stale_conditional" ] && printf '  - re-verify (%s+ days untouched, tier: short with no absolute expiry — nothing will ever archive these; check whether the event already happened): %s\n' "$REVIEW_DAYS" "$stale_conditional"
[ -n "$stale_untiered" ] && printf '  - re-verify (%s+ days untouched, no tier — consolidate may not touch these; re-save through the remember gate): %s\n' "$REVIEW_DAYS" "$stale_untiered"
[ "$drift" -gt 0 ] && printf '  - index drift: %s memory file(s) are newer than MEMORY.md — their one-line summaries may no longer match the body\n' "$drift"
[ -n "$broken" ] && printf '  - index points at missing files: %s\n' "$broken"
[ -n "$orphan" ] && printf '  - memory files missing from the index: %s\n' "$orphan"
[ -n "$index_lines_over" ] && printf '  - MEMORY.md is %s lines\n' "$index_lines_over"
[ -n "$overdue" ] && printf '  - consolidate: %s\n' "$overdue"
printf 'Do not act on this automatically. Offer /memory-loop:consolidate; it proposes and writes only on confirmation. Re-verifying a memory that is still true costs one line: set reviewed: %s in its frontmatter.\n' "$TODAY"

mkdir -p "$STATE_DIR" 2>/dev/null || true
printf '%s' "$TODAY" > "$LAST_REPORT_FILE" 2>/dev/null || true
exit 0
