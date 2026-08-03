#!/usr/bin/env bats
# Tests for scripts/remask-audit.sh — re-mask an existing audit log.

setup() {
  RM="${BATS_TEST_DIRNAME}/../scripts/remask-audit.sh"
  LOG="${BATS_TEST_TMPDIR}/audit.jsonl"
}

@test "re-masks a leaked token in .summary with --apply (and backs up)" {
  tok='ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789'
  jq -cn --arg s "git push https://$tok@x/y" \
    '{ts:"t",tool:"Bash",summary:$s,error:false,cwd:"/x"}' > "$LOG"
  run bash "$RM" --apply "$LOG"
  [ "$status" -eq 0 ]
  run cat "$LOG"
  [[ "$output" != *"$tok"* ]]
  [[ "$output" == *"REDACTED"* ]]
  [ -f "$LOG.premask.bak" ]
}

@test "dry-run leaves the file unchanged and prints no raw secret" {
  tok='ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789'
  jq -cn --arg s "export TOKEN=$tok" '{summary:$s}' > "$LOG"
  before=$(cat "$LOG")
  run bash "$RM" "$LOG"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$before" ]
  [[ "$output" != *"$tok"* ]]
  [[ "$output" == *"would be re-masked"* ]]
  [ ! -f "$LOG.premask.bak" ]
}

@test "idempotent: an already-redacted line is not rewritten" {
  jq -cn '{summary:"export TOKEN=REDACTED"}' > "$LOG"
  before=$(cat "$LOG")
  run bash "$RM" --apply "$LOG"
  [ "$status" -eq 0 ]
  [ "$(cat "$LOG")" = "$before" ]
  [ ! -f "$LOG.premask.bak" ]
}

@test "empty or missing file: exit 0, no crash (boundary)" {
  run bash "$RM" "${BATS_TEST_TMPDIR}/does-not-exist.jsonl"
  [ "$status" -eq 0 ]
  : > "${BATS_TEST_TMPDIR}/empty.jsonl"
  run bash "$RM" --apply "${BATS_TEST_TMPDIR}/empty.jsonl"
  [ "$status" -eq 0 ]
}
