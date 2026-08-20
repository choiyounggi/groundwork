#!/usr/bin/env bash
# groundwork / memory-loop — tutor spaced-repetition scheduler (Leitner).
#
# Deterministic date/state math only — no LLM behavior lives here. Subcommands:
#   due [--count]                        list due item ids (oldest-due first,
#                                         retired excluded, capped at
#                                         tutorSessionCap; --count is uncapped)
#   record <id> <rating 1-4>             append a review, advance box/due
#   add <id> <concept> <model_answer> <source_ref>
#                                         insert a new item at box 0
#   list                                 print items.json
#
# State: ~/.claude/groundwork/memory-loop/tutor/{items.json,reviews.jsonl}.
# Config precedence: <cwd>/.groundwork/memory-loop.json (repo) wins over
# ~/.claude/groundwork/memory-loop.json (global) wins over built-in defaults;
# keys tutorSessionCap (default 3), tutorEnabled (default true).
#
# Design notes:
#   - Read verbs (due, list) fail OPEN on corrupt items.json: warn on stderr,
#     treat as {"items":[]}, exit 0. Write verbs (add, record) fail CLOSED:
#     refuse with exit 2 rather than write over state we can't trust.
#   - record() appends to reviews.jsonl BEFORE updating items.json, so a
#     crash mid-write leaves a logged review with unadvanced state (a re-
#     record converges) rather than an advanced item with no log entry.
#   - items.json is written atomically: tmp file in the same dir, then mv.
#   - Date math is epoch-based (never relative-date flags like -v+Nd or
#     -d "+N days") so the same arithmetic works on BSD and GNU date; the
#     formatter/parser flavor is feature-detected once at startup.
#   - TUTOR_TODAY (ISO YYYY-MM-DD, UTC) overrides "today" for tests; unset
#     or empty means use the real date.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

STATE_DIR="${HOME}/.claude/groundwork/memory-loop/tutor"
ITEMS_FILE="${STATE_DIR}/items.json"
REVIEWS_FILE="${STATE_DIR}/reviews.jsonl"

GLOBAL_CFG="${HOME}/.claude/groundwork/memory-loop.json"
REPO_CFG="${PWD}/.groundwork/memory-loop.json"

# --- config --------------------------------------------------------------

# config_get <key> <default> — first config file (repo, then global) that
# defines the key wins, whatever its value (including false/0); corrupt
# config files are skipped, not fatal.
config_get() {
  local key="$1" default="$2" cfg v
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    if jq -e --arg k "$key" 'has($k)' "$cfg" >/dev/null 2>&1; then
      v=$(jq -r --arg k "$key" '.[$k]' "$cfg" 2>/dev/null || true)
      printf '%s' "$v"
      return 0
    fi
  done
  printf '%s' "$default"
}

TUTOR_SESSION_CAP=$(config_get tutorSessionCap 3)
case "$TUTOR_SESSION_CAP" in ''|*[!0-9]*|0) TUTOR_SESSION_CAP=3 ;; esac

TUTOR_ENABLED_RAW=$(config_get tutorEnabled true)
case "$TUTOR_ENABLED_RAW" in
  true) TUTOR_ENABLED=true ;;
  false) TUTOR_ENABLED=false ;;
  *) TUTOR_ENABLED=true ;;
esac

# --- date helpers ----------------------------------------------------------

# Feature-detect the date(1) flavor once. BSD date (macOS) accepts -r <epoch>
# and -j -f <fmt> <string>; GNU date accepts -d @<epoch> and -d <string>.
if date -u -r 0 +%Y-%m-%d >/dev/null 2>&1; then
  DATE_STYLE=bsd
else
  DATE_STYLE=gnu
fi

today_iso() {
  if [ -n "${TUTOR_TODAY:-}" ]; then
    printf '%s' "$TUTOR_TODAY"
  else
    date -u +%Y-%m-%d
  fi
}

iso_to_epoch() {
  local iso="$1"
  if [ "$DATE_STYLE" = bsd ]; then
    date -j -u -f '%Y-%m-%d' "$iso" +%s 2>/dev/null
  else
    date -u -d "$iso" +%s 2>/dev/null
  fi
}

epoch_to_iso() {
  local epoch="$1"
  if [ "$DATE_STYLE" = bsd ]; then
    date -u -r "$epoch" +%Y-%m-%d
  else
    date -u -d "@$epoch" +%Y-%m-%d
  fi
}

today_epoch() {
  iso_to_epoch "$(today_iso)"
}

# interval_for_box <box 0-4> — Leitner intervals in days.
interval_for_box() {
  case "$1" in
    0) echo 1 ;;
    1) echo 3 ;;
    2) echo 7 ;;
    3) echo 21 ;;
    4) echo 60 ;;
    *) echo 1 ;;
  esac
}

due_after_box() {
  local box="$1" interval due_epoch
  interval=$(interval_for_box "$box")
  due_epoch=$(( $(today_epoch) + interval * 86400 ))
  epoch_to_iso "$due_epoch"
}

# --- state I/O ---------------------------------------------------------

validate_items_file() {
  jq -e 'has("items") and (.items | type == "array")' "$1" >/dev/null 2>&1
}

# read_items_or_empty — for read verbs. Missing or corrupt state degrades to
# {"items":[]}; corrupt state warns on stderr. Always exit 0 (fail-open).
read_items_or_empty() {
  if [ ! -f "$ITEMS_FILE" ]; then
    printf '%s' '{"items":[]}'
    return 0
  fi
  if validate_items_file "$ITEMS_FILE"; then
    cat "$ITEMS_FILE"
  else
    echo "tutor-schedule: warning: corrupt items.json, treating as empty" >&2
    printf '%s' '{"items":[]}'
  fi
}

# read_items_or_fail — for write verbs. Missing state degrades to
# {"items":[]}; corrupt state refuses (return 1) rather than write over it.
read_items_or_fail() {
  if [ ! -f "$ITEMS_FILE" ]; then
    printf '%s' '{"items":[]}'
    return 0
  fi
  if validate_items_file "$ITEMS_FILE"; then
    cat "$ITEMS_FILE"
  else
    echo "tutor-schedule: error: corrupt items.json, refusing to write" >&2
    return 1
  fi
}

write_items() {
  local content="$1" tmp="${ITEMS_FILE}.tmp.$$"
  printf '%s' "$content" > "$tmp"
  mv "$tmp" "$ITEMS_FILE"
}

# --- subcommands -----------------------------------------------------------

cmd_list() {
  read_items_or_empty
  echo
  exit 0
}

cmd_due() {
  local count_only=false
  if [ "${1:-}" = "--count" ]; then count_only=true; fi

  if [ "$TUTOR_ENABLED" = "false" ]; then
    if [ "$count_only" = true ]; then echo 0; fi
    exit 0
  fi

  local items today due_ids
  items=$(read_items_or_empty)
  today=$(today_iso)

  due_ids=$(printf '%s' "$items" | jq -r --arg today "$today" '
    [.items[]? | select((.retired // false) == false) | select(.due <= $today)]
    | sort_by(.due)
    | .[].id
  ' 2>/dev/null || true)

  if [ "$count_only" = true ]; then
    if [ -z "$due_ids" ]; then
      echo 0
    else
      printf '%s\n' "$due_ids" | wc -l | tr -d ' '
    fi
    exit 0
  fi

  [ -z "$due_ids" ] && exit 0
  printf '%s\n' "$due_ids" | head -n "$TUTOR_SESSION_CAP"
  exit 0
}

cmd_add() {
  local id="${1:-}" concept="${2:-}" model_answer="${3:-}" source_ref="${4:-}"
  if [ -z "$id" ] || [ -z "$concept" ] || [ -z "$model_answer" ] || [ -z "$source_ref" ]; then
    echo "tutor-schedule: error: add requires <id> <concept> <model_answer> <source_ref>" >&2
    exit 2
  fi

  local items
  items=$(read_items_or_fail) || exit 2

  if printf '%s' "$items" | jq -e --arg id "$id" '.items[]? | select(.id == $id)' >/dev/null 2>&1; then
    echo "tutor-schedule: error: item '$id' already exists" >&2
    exit 2
  fi

  local today new_items
  today=$(today_iso)
  new_items=$(printf '%s' "$items" | jq \
    --arg id "$id" --arg concept "$concept" \
    --arg model_answer "$model_answer" --arg source_ref "$source_ref" \
    --arg due "$today" '
    .items += [{
      id: $id, concept: $concept, model_answer: $model_answer,
      source_ref: $source_ref, box: 0, due: $due,
      streak_ge_21d: 0, retired: false
    }]
  ')

  mkdir -p "$STATE_DIR"
  write_items "$new_items"
  exit 0
}

cmd_record() {
  local id="${1:-}" rating="${2:-}"
  case "$rating" in
    1|2|3|4) : ;;
    *)
      echo "tutor-schedule: error: rating must be 1-4, got '$rating'" >&2
      exit 2
      ;;
  esac

  local items
  items=$(read_items_or_fail) || exit 2

  if ! printf '%s' "$items" | jq -e --arg id "$id" '.items[]? | select(.id == $id)' >/dev/null 2>&1; then
    echo "tutor-schedule: error: unknown item id '$id'" >&2
    exit 2
  fi

  local cur_box cur_streak
  cur_box=$(printf '%s' "$items" | jq -r --arg id "$id" '.items[] | select(.id == $id) | .box')
  cur_streak=$(printf '%s' "$items" | jq -r --arg id "$id" '.items[] | select(.id == $id) | .streak_ge_21d')

  local new_box new_streak
  case "$rating" in
    1)
      new_box=0
      new_streak=0
      ;;
    2)
      new_box="$cur_box"
      new_streak=0
      ;;
    3|4)
      if [ "$cur_box" -ge 4 ]; then new_box=4; else new_box=$((cur_box + 1)); fi
      if [ "$cur_box" -ge 3 ]; then
        new_streak=$((cur_streak + 1))
      else
        new_streak=0
      fi
      ;;
  esac

  local new_due new_retired
  new_due=$(due_after_box "$new_box")
  new_retired=false
  [ "$new_streak" -ge 3 ] && new_retired=true

  mkdir -p "$STATE_DIR"

  # Append the review log first (D3): a crash between this and the items.json
  # write leaves a logged review with unadvanced state, not the reverse.
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -cn --arg id "$id" --argjson rating "$rating" --arg ts "$ts" \
    '{item_id: $id, rating: $rating, ts: $ts}' >> "$REVIEWS_FILE"

  local new_items
  new_items=$(printf '%s' "$items" | jq \
    --arg id "$id" --argjson box "$new_box" --arg due "$new_due" \
    --argjson streak "$new_streak" --argjson retired "$new_retired" '
    .items = [.items[] | if .id == $id then
      .box = $box | .due = $due | .streak_ge_21d = $streak | .retired = $retired
    else . end]
  ')

  write_items "$new_items"
  exit 0
}

# --- dispatch ----------------------------------------------------------

usage() {
  echo "usage: tutor-schedule.sh due [--count] | record <id> <rating> | add <id> <concept> <model_answer> <source_ref> | list" >&2
}

main() {
  local cmd="${1:-}"
  [ $# -gt 0 ] && shift
  case "$cmd" in
    due) cmd_due "$@" ;;
    record) cmd_record "$@" ;;
    add) cmd_add "$@" ;;
    list) cmd_list ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
