#!/usr/bin/env bats
# Tests for hooks/audit-log.sh.

setup() {
  AUDIT="${BATS_TEST_DIRNAME}/../hooks/audit-log.sh"
  export GROUNDWORK_AUDIT_LOG="$BATS_TEST_TMPDIR/audit.jsonl"
}

@test "logs a bash command as one JSONL record" {
  jq -cn '{tool_name:"Bash",tool_input:{command:"ls -la"},cwd:"/x"}' | bash "$AUDIT"
  run cat "$GROUNDWORK_AUDIT_LOG"
  [[ "$output" == *'"tool":"Bash"'* ]]
  [[ "$output" == *'ls -la'* ]]
}

@test "redacts a GitHub token" {
  tok="ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
  jq -cn --arg c "git push https://$tok@github.com/x/y" \
    '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$AUDIT"
  run cat "$GROUNDWORK_AUDIT_LOG"
  [[ "$output" != *"$tok"* ]]
  [[ "$output" == *"REDACTED"* ]]
}

@test "never fails on malformed input" {
  run bash -c "printf 'not json' | bash '$AUDIT'"
  [ "$status" -eq 0 ]
}

@test "writes nothing when tool_name is absent" {
  jq -cn '{tool_input:{command:"ls"}}' | bash "$AUDIT"
  [ ! -s "$GROUNDWORK_AUDIT_LOG" ]
}
