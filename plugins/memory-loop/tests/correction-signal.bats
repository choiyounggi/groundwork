#!/usr/bin/env bats
# Tests for hooks/correction-signal.sh.
# Every detected correction is recorded (without the prompt text); the context
# line is injected at most correctionInjectionCap times per session; malformed
# input and non-corrections stay silent.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/correction-signal.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.claude/groundwork/memory-loop"
  mkdir -p "$STATE"
  CTX='Correction signal: that looked like a correction. If it points to a repeated mistake, consider capturing a habit (memory-loop "habit" skill) or saving a memory (memory-loop "remember" skill); otherwise continue.'
}

teardown() {
  # the unwritable-dir cases chmod parts of $HOME; restore so bats can clean up
  chmod -R u+w "$HOME" 2>/dev/null || true
}

run_hook() {
  # $1 = prompt text, $2 = session_id (default "sess1")
  jq -cn --arg p "$1" --arg sid "${2:-sess1}" '{prompt: $p, session_id: $sid}' | bash "$HOOK"
}

signal_lines() {
  if [ -f "$STATE/signals.jsonl" ]; then wc -l < "$STATE/signals.jsonl" | tr -d ' '; else printf '0'; fi
}

@test "normal: a Korean correction injects the context line and records its keywords" {
  run run_hook "아니야, 그게 아니라 다른 파일이야"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "UserPromptSubmit" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  [ "$(signal_lines)" = "1" ]
  line=$(head -1 "$STATE/signals.jsonl")
  [ "$(printf '%s' "$line" | jq -c '.matched')" = '["아니","그게아니라"]' ]
  [ "$(printf '%s' "$line" | jq -c 'keys')" = '["matched","session_id","ts"]' ]
  [ "$(printf '%s' "$line" | jq -r '.session_id')" = "sess1" ]
  [[ "$(printf '%s' "$line" | jq -r '.ts')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "normal: a non-correction prompt is silent and records nothing" {
  run run_hook "add a new test for the parser"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "0" ]
}

@test "error: malformed JSON on stdin exits 0 silently and records nothing" {
  run bash -c 'echo "not json" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "0" ]
}

@test "error: empty stdin exits 0 silently and records nothing" {
  run bash -c 'printf "" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "0" ]
}

@test "privacy: the prompt text never reaches signals.jsonl" {
  prompt="wrong again, the secret-marker-7f3a file is elsewhere"
  run run_hook "$prompt"
  [ "$status" -eq 0 ]
  [ "$(signal_lines)" = "1" ]
  [ "$(jq -c '.matched' "$STATE/signals.jsonl")" = '["wrong"]' ]
  run grep -F "secret-marker-7f3a" "$STATE/signals.jsonl"
  [ "$status" -eq 1 ]
  run grep -F "$prompt" "$STATE/signals.jsonl"
  [ "$status" -eq 1 ]
}

@test "boundary: the 3rd match still injects, the 4th records without injecting" {
  for i in 1 2 3; do
    run run_hook "그거 틀렸어"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  done
  run run_hook "그거 틀렸어"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "4" ]
}

@test "boundary: a different session starts with a fresh cap" {
  for i in 1 2 3; do run_hook "그거 틀렸어" sess1 >/dev/null; done
  run run_hook "그거 틀렸어" sess1
  [ -z "$output" ]
  run run_hook "그거 틀렸어" sess2
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  [ "$(signal_lines)" = "5" ]
}

@test "boundary: correctionInjectionCap 0 disables injection but still records" {
  printf '{"correctionInjectionCap": 0}' > "$HOME/.claude/groundwork/memory-loop.json"
  run run_hook "wrong, do it again"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "1" ]
  [ "$(jq -c '.matched' "$STATE/signals.jsonl")" = '["wrong"]' ]
}

@test "false positive: 아니면 is not a correction" {
  run run_hook "아니면 다른 방법도 괜찮아"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "0" ]
}

@test "pruning: session state idle for more than 2 days is removed, fresh state kept" {
  mkdir -p "$STATE/correction-sessions"
  printf '9' > "$STATE/correction-sessions/stale"
  touch -t 202001010000 "$STATE/correction-sessions/stale"
  printf '1' > "$STATE/correction-sessions/fresh"
  run run_hook "그거 틀렸어" sess3
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/correction-sessions/stale" ]
  [ -e "$STATE/correction-sessions/fresh" ]
  [ "$(cat "$STATE/correction-sessions/sess3")" = "1" ]
}

@test "error: unwritable groundwork dir exits 0 with no stdout, no stderr, no record" {
  rmdir "$STATE"
  chmod 555 "$HOME/.claude/groundwork"
  run --separate-stderr run_hook "that is wrong"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$STATE" ]
}

@test "error: unwritable correction-sessions dir never injects (cap unenforceable) and stays silent" {
  mkdir -p "$STATE/correction-sessions"
  chmod 555 "$STATE/correction-sessions"
  for i in 1 2 3 4; do
    run --separate-stderr run_hook "that is wrong"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
  done
  [ "$(signal_lines)" = "4" ]
  [ -z "$(ls -A "$STATE/correction-sessions")" ]
}

@test "error: read-only state dir with a writable correction-sessions dir fails the append silently, cap still enforced" {
  mkdir -p "$STATE/correction-sessions"
  chmod 555 "$STATE"
  run --separate-stderr run_hook "that is wrong"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  [ ! -e "$STATE/signals.jsonl" ]
  [ "$(cat "$STATE/correction-sessions/sess1")" = "1" ]
}

@test "normal: don’t with a curly apostrophe (U+2019) is labelled dont" {
  run run_hook "$(printf 'don\342\200\231t touch that file')"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  [ "$(jq -c '.matched' "$STATE/signals.jsonl")" = '["dont"]' ]
}

@test "normal: don't with an ASCII apostrophe is labelled dont" {
  run run_hook "don't touch that file"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" = "$CTX" ]
  [ "$(jq -c '.matched' "$STATE/signals.jsonl")" = '["dont"]' ]
}

@test "boundary: an apostrophe other than ' or ’ between don and t is not a match" {
  run run_hook "$(printf 'don\342\200\230t touch that file')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(signal_lines)" = "0" ]
}
