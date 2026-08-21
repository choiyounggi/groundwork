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

# --- HABITS.md split guard -------------------------------------------------
# HABITS.md is imported into every session, so it is re-read on every request.
# Past a byte threshold the nudge also asks for background prose to move into
# HABITS-CASES.md. Bidirectional: it must stay quiet below the threshold, or
# the reminder becomes noise that gets ignored.

make_habits() {                      # $1 = size in bytes
  mkdir -p "$HOME/.claude/groundwork"
  head -c "$1" /dev/zero | tr '\0' 'x' > "$HOME/.claude/groundwork/HABITS.md"
}

@test "split guard: no HABITS.md means no split notice" {
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" != *"split threshold"* ]]
}

@test "split guard: below the threshold stays quiet" {
  make_habits 1000
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" != *"split threshold"* ]]
}

@test "split guard: above the threshold names the size, the limit, and the target file" {
  make_habits 50000
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" == *"split threshold"* ]]
  [[ "$reason" == *"50000 bytes"* ]]
  [[ "$reason" == *"40000-byte"* ]]
  [[ "$reason" == *"HABITS-CASES.md"* ]]
  [[ "$reason" == *"hard lines inline"* ]]
  # the learning review itself must still be there
  [[ "$reason" == *"Learning review"* ]]
}

@test "split guard: habitsSplitWarnBytes 0 disables the check" {
  make_habits 50000
  printf '{"habitsSplitWarnBytes": 0}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" != *"split threshold"* ]]
}

@test "split guard: a custom threshold is honored and reported" {
  make_habits 2000
  printf '{"habitsSplitWarnBytes": 1000}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" == *"split threshold"* ]]
  [[ "$reason" == *"1000-byte"* ]]
}

@test "split guard: repo config wins over global for habitsSplitWarnBytes" {
  make_habits 5000
  printf '{"habitsSplitWarnBytes": 99999}' > "$HOME/.claude/groundwork/memory-loop.json"
  mkdir -p "$BATS_TEST_TMPDIR/repo/.groundwork"
  printf '{"habitsSplitWarnBytes": 1000}' > "$BATS_TEST_TMPDIR/repo/.groundwork/memory-loop.json"
  printf '9' > "$STATE/nudge-counter"
  run bash -c 'cd "$1" && jq -cn "{stop_hook_active: false}" | bash "$2"' _ "$BATS_TEST_TMPDIR/repo" "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" == *"split threshold"* ]]
}

@test "split guard: non-numeric habitsSplitWarnBytes falls back to 40000" {
  make_habits 50000
  printf '{"habitsSplitWarnBytes": "big"}' > "$HOME/.claude/groundwork/memory-loop.json"
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.reason')" == *"40000-byte"* ]]
}

# A HABITS.md predating the two-file layout has no cases file beside it, and a
# plugin update does not create one (setup never overwrites). The notice must
# say so rather than pointing at a file that isn't there — and must stop saying
# it once the file exists.

@test "split guard: without a cases file the notice explains the migration" {
  make_habits 50000
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" == *"predates the two-file layout"* ]]
  [[ "$reason" == *"setup skill"* ]]
  [[ "$reason" == *"without touching HABITS.md"* ]]
}

@test "split guard: with a cases file the migration wording is gone" {
  make_habits 50000
  printf 'x' > "$HOME/.claude/groundwork/HABITS-CASES.md"
  printf '9' > "$STATE/nudge-counter"
  run run_hook
  [ "$status" -eq 0 ]
  reason=$(printf '%s' "$output" | jq -r '.reason')
  [[ "$reason" != *"predates the two-file layout"* ]]
  # the split advice itself must survive
  [[ "$reason" == *"split threshold"* ]]
  [[ "$reason" == *"[Cnn] pointer"* ]]
}
