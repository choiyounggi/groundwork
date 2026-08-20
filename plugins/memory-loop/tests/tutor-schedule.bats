#!/usr/bin/env bats
# Tests for skills/tutor/scripts/tutor-schedule.sh — deterministic Leitner
# scheduler CLI + FSRS-compatible review log. TUTOR_TODAY pins "today" so
# box/due math is provable; $HOME is sandboxed so state never touches the
# real machine.

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../skills/tutor/scripts/tutor-schedule.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  STATE="$HOME/.claude/groundwork/memory-loop/tutor"
  export TUTOR_TODAY="2026-01-15"
}

run_cli() {
  bash "$SCRIPT" "$@"
}

add_item() {
  run_cli add "$1" "concept-$1" "answer-$1" "source-$1"
}

# Directly patch a field on an item in items.json — used only to seed
# boundary-case state (e.g. box already at 3) without needing a long chain
# of real record() calls to get there.
seed_field() {
  local id="$1" key="$2" value="$3"
  local tmp="$STATE/items.json.seedtmp"
  jq --arg id "$id" --arg key "$key" --argjson value "$value" '
    .items = [.items[] | if .id == $id then .[$key] = $value else . end]
  ' "$STATE/items.json" > "$tmp"
  mv "$tmp" "$STATE/items.json"
}

# ---------- normal ----------

@test "list on absent state prints empty items json" {
  run run_cli list
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.items | length')" = "0" ]
}

@test "add then due then record: item appears due, record advances box and due date" {
  run add_item item-1
  [ "$status" -eq 0 ]

  run run_cli due
  [ "$status" -eq 0 ]
  [ "$output" = "item-1" ]

  run run_cli record item-1 3
  [ "$status" -eq 0 ]

  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].box')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].due')" = "2026-01-18" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].retired')" = "false" ]
}

@test "record appends a valid FSRS-shaped reviews.jsonl line" {
  add_item item-1
  run run_cli record item-1 4
  [ "$status" -eq 0 ]

  local line
  line=$(cat "$STATE/reviews.jsonl")
  [ "$(printf '%s' "$line" | jq -r '.item_id')" = "item-1" ]
  [ "$(printf '%s' "$line" | jq -r '.rating')" = "4" ]
  [[ "$(printf '%s' "$line" | jq -r '.ts')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "add rejects a duplicate id with exit 2" {
  add_item item-1
  run add_item item-1
  [ "$status" -eq 2 ]
}

# ---------- error ----------

@test "record with an unknown id exits 2 with a stderr message" {
  add_item item-1
  run run_cli record ghost 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"ghost"* ]]
}

@test "record with an out-of-range rating (0) exits 2" {
  add_item item-1
  run run_cli record item-1 0
  [ "$status" -eq 2 ]
}

@test "record with an out-of-range rating (5) exits 2" {
  add_item item-1
  run run_cli record item-1 5
  [ "$status" -eq 2 ]
}

@test "corrupt items.json on a read verb (due) fails open: empty, exit 0" {
  mkdir -p "$STATE"
  printf 'not json' > "$STATE/items.json"
  run --separate-stderr run_cli due
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"corrupt"* ]]
}

@test "corrupt items.json on a write verb (record) fails closed: exit 2" {
  mkdir -p "$STATE"
  printf 'not json' > "$STATE/items.json"
  run run_cli record item-1 3
  [ "$status" -eq 2 ]
}

@test "corrupt items.json on a write verb (add) fails closed: exit 2" {
  mkdir -p "$STATE"
  printf 'not json' > "$STATE/items.json"
  run run_cli add item-1 concept answer source
  [ "$status" -eq 2 ]
}

# ---------- boundary ----------

@test "empty state: due prints nothing and due --count prints 0" {
  run run_cli due
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_cli due --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "due caps at exactly tutorSessionCap while --count stays uncapped" {
  add_item item-1
  add_item item-2
  add_item item-3
  add_item item-4
  add_item item-5

  run run_cli due --count
  [ "$status" -eq 0 ]
  [ "$output" = "5" ]

  run run_cli due
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "box already at 4 stays at 4 on rating 4, due advances by the 60d interval" {
  add_item item-1
  seed_field item-1 box 4

  run run_cli record item-1 4
  [ "$status" -eq 0 ]

  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].box')" = "4" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].due')" = "2026-03-16" ]
}

@test "rating 1 fully resets: box to 0, streak to 0, due +1d" {
  add_item item-1
  seed_field item-1 box 3
  seed_field item-1 streak_ge_21d 2

  run run_cli record item-1 1
  [ "$status" -eq 0 ]

  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].box')" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].due')" = "2026-01-16" ]
}

@test "rating 2 keeps the box, resets streak, due advances by the current box's interval" {
  add_item item-1
  seed_field item-1 box 2
  seed_field item-1 streak_ge_21d 1

  run run_cli record item-1 2
  [ "$status" -eq 0 ]

  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].box')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "0" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].due')" = "2026-01-22" ]
}

@test "retirement triggers exactly on the 3rd consecutive rating>=3 review at box>=3" {
  add_item item-1
  seed_field item-1 box 3
  seed_field item-1 streak_ge_21d 0

  run run_cli record item-1 3
  [ "$status" -eq 0 ]
  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "1" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].retired')" = "false" ]

  run run_cli record item-1 3
  [ "$status" -eq 0 ]
  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "2" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].retired')" = "false" ]

  run run_cli record item-1 3
  [ "$status" -eq 0 ]
  run run_cli list
  [ "$(printf '%s' "$output" | jq -r '.items[0].streak_ge_21d')" = "3" ]
  [ "$(printf '%s' "$output" | jq -r '.items[0].retired')" = "true" ]
}

@test "a retired item, even if past due, is excluded from due" {
  add_item item-1
  seed_field item-1 due '"2020-01-01"'
  seed_field item-1 retired true

  run run_cli due
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_cli due --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "tutorEnabled=false: due prints nothing and due --count prints 0" {
  add_item item-1
  mkdir -p "$HOME/.claude/groundwork"
  printf '{"tutorEnabled": false}' > "$HOME/.claude/groundwork/memory-loop.json"

  run run_cli due
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_cli due --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "repo config overrides global config for tutorSessionCap" {
  add_item item-1
  add_item item-2
  add_item item-3

  mkdir -p "$HOME/.claude/groundwork" "$BATS_TEST_TMPDIR/repo/.groundwork"
  printf '{"tutorSessionCap": 5}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '{"tutorSessionCap": 1}' > "$BATS_TEST_TMPDIR/repo/.groundwork/memory-loop.json"

  run bash -c 'cd "$1" && TUTOR_TODAY="$2" bash "$3" due' _ "$BATS_TEST_TMPDIR/repo" "$TUTOR_TODAY" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
}
