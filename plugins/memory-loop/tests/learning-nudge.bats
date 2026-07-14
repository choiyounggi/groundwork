#!/usr/bin/env bats
# Tests for hooks/learning-nudge.sh.
# Bidirectional by design: the nudge fires exactly at the interval and stays
# silent below it; the stop_hook_active loop guard and corrupt state must be
# provably safe.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/learning-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.claude/groundwork/memory-loop"
  mkdir -p "$STATE"
}

run_hook() {
  jq -cn '{stop_hook_active: false}' | bash "$HOOK"
}

@test "below the interval: silent, counter incremented" {
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$STATE/nudge-counter")" = "1" ]
}

@test "reaching the interval: emits block JSON and resets the counter" {
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" == *"Learning review"* ]]
  [ "$(cat "$STATE/nudge-counter")" = "0" ]
}

@test "custom nudgeInterval from the global config is honored" {
  mkdir -p "$HOME/.claude/groundwork"
  printf '{"nudgeInterval": 2}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '1' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "repo config wins over global config for nudgeInterval" {
  mkdir -p "$HOME/.claude/groundwork" "$BATS_TEST_TMPDIR/repo/.groundwork"
  printf '{"nudgeInterval": 50}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '{"nudgeInterval": 2}' > "$BATS_TEST_TMPDIR/repo/.groundwork/memory-loop.json"
  printf '1' > "$STATE/nudge-counter"
  run bash -c 'cd "$1" && jq -cn "{stop_hook_active: false}" | bash "$2"' _ "$BATS_TEST_TMPDIR/repo" "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}

@test "stop_hook_active short-circuits before counting" {
  printf '9' > "$STATE/nudge-counter"
  run bash -c 'jq -cn "{stop_hook_active: true}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$STATE/nudge-counter")" = "9" ]
}

@test "corrupt counter file is treated as zero" {
  printf 'abc' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$STATE/nudge-counter")" = "1" ]
}

@test "non-numeric nudgeInterval falls back to the default of 10" {
  mkdir -p "$HOME/.claude/groundwork"
  printf '{"nudgeInterval": "lots"}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "block" ]
}
