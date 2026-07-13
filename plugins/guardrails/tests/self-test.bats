#!/usr/bin/env bats
# Tests for scripts/self-test.sh.

setup() {
  ST="${BATS_TEST_DIRNAME}/../scripts/self-test.sh"
}

@test "self-test exits 0 (all cases match expected decisions)" {
  run bash "$ST"
  [ "$status" -eq 0 ]
}

@test "self-test reports a deny and an ask" {
  run bash "$ST"
  [[ "$output" == *"deny"* ]]
  [[ "$output" == *"ask"* ]]
}

@test "self-test states nothing was executed" {
  run bash "$ST"
  [[ "$output" == *"Nothing ran"* || "$output" == *"nothing"* || "$output" == *"executed"* ]]
}

@test "self-test does not actually create files from its example commands" {
  ( cd "$BATS_TEST_TMPDIR" && bash "$ST" >/dev/null 2>&1 )
  [ ! -e "$BATS_TEST_TMPDIR/build" ]
  run bash -c "ls -a '$BATS_TEST_TMPDIR' | wc -l"
  [ "$output" -le 3 ]
}
