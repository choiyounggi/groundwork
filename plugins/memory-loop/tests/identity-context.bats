#!/usr/bin/env bats
# Tests for hooks/identity-context.sh.
# The three branches (unset / set / declined) are the behaviors; malformed and
# partial state must be provably silent (fail-open), and a broken file must
# NOT re-trigger the one-time setup offer.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/identity-context.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.claude/groundwork/memory-loop"
  mkdir -p "$STATE"
  IDENTITY="$STATE/identity.json"
}

run_hook() {
  printf '{}' | bash "$HOOK"
}

@test "unset (no file): prints the one-time setup offer" {
  rm -f "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"[memory-loop] No identity"* ]]
  [[ "$output" == *"one-time name setup"* ]]
  [[ "$output" == *"what the user would like to be called"* ]]
  [[ "$output" == *"you choose a name yourself"* ]]
}

@test "set: injects both names, no self-chosen sentence for chosenBy=user" {
  jq -cn '{userName: "Sam", assistantName: "Iris", chosenBy: "user", status: "set"}' \
    > "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"The user's name is Sam."* ]]
  [[ "$output" == *"Your name is Iris."* ]]
  [[ "$output" == *"Address each other by name."* ]]
  [[ "$output" != *"chose this name"* ]]
}

@test "set with chosenBy=assistant: adds the self-chosen sentence" {
  jq -cn '{userName: "Sam", assistantName: "Iris", chosenBy: "assistant", status: "set"}' \
    > "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Your name is Iris."* ]]
  [[ "$output" == *"You chose this name yourself."* ]]
}

@test "declined: stays silent" {
  jq -cn '{status: "declined"}' > "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed JSON: silent fail-open, does NOT re-offer setup" {
  printf '{oops' > "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "partial identity (missing assistantName): silent" {
  jq -cn '{userName: "Sam", status: "set"}' > "$IDENTITY"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
