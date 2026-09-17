#!/usr/bin/env bats
# Tests for hooks/habits-budget-guard.sh.
# Bidirectional by design: the guard must deny growth past the budget AND must
# never block the way out — a write that shrinks an over-budget file is always
# allowed, or the file would be frozen in the state the guard exists to fix.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/habits-budget-guard.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  GW="$HOME/.claude/groundwork"
  HABITS="$GW/HABITS.md"
  mkdir -p "$GW"
}

# A habit file of exactly $1 bytes (padding is a comment line, never a rule).
seed_habits() {
  local want="$1" head="# HABITS"$'\n'
  local pad=$((want - ${#head}))
  { printf '%s' "$head"; [ "$pad" -gt 0 ] && head -c "$pad" < /dev/zero | tr '\0' 'x'; } > "$HABITS"
}

seed_rules() {
  # $1 rules, each a valid `- **…` line.
  local n="$1" i=1
  : > "$HABITS"
  while [ "$i" -le "$n" ]; do
    printf -- '- **rule %s**\n' "$i" >> "$HABITS"
    i=$((i + 1))
  done
}

write_call() {
  # $1 = file_path, $2 = content
  jq -cn --arg p "$1" --arg c "$2" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}' | bash "$HOOK"
}

edit_call() {
  # $1 = file_path, $2 = old_string, $3 = new_string
  jq -cn --arg p "$1" --arg o "$2" --arg n "$3" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}' | bash "$HOOK"
}

decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision'; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

@test "a file that is not the habit file is ignored" {
  seed_habits 100
  run write_call "$HOME/somewhere/else.md" "$(head -c 12000 < /dev/zero | tr '\0' 'y')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a tool other than Edit/Write is ignored" {
  seed_habits 100
  run bash -c "jq -cn --arg p '$HABITS' '{tool_name: \"Read\", tool_input: {file_path: \$p}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Write past the byte budget is denied and the message names both sizes" {
  seed_habits 100
  run write_call "$HABITS" "$(head -c 9000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"8000"* ]]
  [[ "$(reason "$output")" == *"9000"* ]]
  [[ "$(reason "$output")" == *"HABITS-ARCHIVE.md"* ]]
}

@test "Write that shrinks an over-budget file is allowed" {
  seed_habits 12000
  run write_call "$HABITS" "$(head -c 11000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Write exactly at the budget is allowed; one byte over is denied" {
  seed_habits 100
  run write_call "$HABITS" "$(head -c 8000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run write_call "$HABITS" "$(head -c 8001 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
}

@test "Edit growth is measured against the current file size" {
  seed_habits 7950
  # +100 bytes: 7950 - 10 + 110 = 8050 > 8000
  run edit_call "$HABITS" "$(head -c 10 < /dev/zero | tr '\0' 'x')" "$(head -c 110 < /dev/zero | tr '\0' 'x')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"8050"* ]]
}

@test "Edit that stays under the budget is allowed" {
  seed_habits 7000
  run edit_call "$HABITS" "$(head -c 10 < /dev/zero | tr '\0' 'x')" "$(head -c 110 < /dev/zero | tr '\0' 'x')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Edit that removes more than it adds is allowed even over budget" {
  seed_habits 12000
  run edit_call "$HABITS" "$(head -c 500 < /dev/zero | tr '\0' 'x')" "short"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the rule cap denies a 25th rule while the file is well under the byte budget" {
  seed_rules 24
  run edit_call "$HABITS" "- **rule 24**" "- **rule 24**
- **rule 25**"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"25"* ]]
  [[ "$(reason "$output")" == *"24"* ]]
}

@test "replacing one rule with another at the cap is allowed" {
  seed_rules 24
  run edit_call "$HABITS" "- **rule 24**" "- **rule twenty-four, merged**"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "custom budget from the global config is honored" {
  printf '{"habitsBudgetBytes": 200}' > "$GW/memory-loop.json"
  seed_habits 100
  run write_call "$HABITS" "$(head -c 300 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"200"* ]]
}

@test "repo config wins over global config" {
  printf '{"habitsBudgetBytes": 200}' > "$GW/memory-loop.json"
  mkdir -p "$BATS_TEST_TMPDIR/repo/.groundwork"
  printf '{"habitsBudgetBytes": 9000}' > "$BATS_TEST_TMPDIR/repo/.groundwork/memory-loop.json"
  seed_habits 100
  cd "$BATS_TEST_TMPDIR/repo"
  run write_call "$HABITS" "$(head -c 300 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "both checks disabled by zero means no decision at any size" {
  printf '{"habitsBudgetBytes": 0, "habitsMaxRules": 0}' > "$GW/memory-loop.json"
  seed_habits 100
  run write_call "$HABITS" "$(head -c 90000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a non-numeric budget falls back to the 8000 default" {
  printf '{"habitsBudgetBytes": "lots"}' > "$GW/memory-loop.json"
  seed_habits 100
  run write_call "$HABITS" "$(head -c 9000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"8000"* ]]
}

@test "a ~ prefixed habitsPath is expanded and guarded" {
  printf '{"habitsPath": "~/.claude/groundwork/OWN.md"}' > "$GW/memory-loop.json"
  printf '# own\n' > "$GW/OWN.md"
  run write_call "$GW/OWN.md" "$(head -c 9000 < /dev/zero | tr '\0' 'z')"
  [ "$status" -eq 0 ]
  [ "$(decision "$output")" = "deny" ]
  [[ "$(reason "$output")" == *"OWN.md"* ]]
}

@test "creating the habit file from nothing is allowed under budget" {
  run write_call "$HABITS" "# HABITS"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty input exits silently" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed JSON input fails open" {
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a Write with no file_path fails open" {
  run bash -c "jq -cn '{tool_name: \"Write\", tool_input: {content: \"x\"}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
