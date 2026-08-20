#!/usr/bin/env bats
# Tests for hooks/tutor-due-check.sh — SessionStart due-item reminder.
# The hook delegates all counting to the merged scheduler CLI
# (skills/tutor/scripts/tutor-schedule.sh); these tests seed real state
# through that CLI so the count is provable, and stub/omit the scheduler to
# prove the hook fails open on every error path.

bats_require_minimum_version 1.5.0

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/tutor-due-check.sh"
  SCHEDULER="${BATS_TEST_DIRNAME}/../skills/tutor/scripts/tutor-schedule.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export TUTOR_TODAY="2026-01-15"
  unset CLAUDE_PLUGIN_ROOT
}

run_hook() {
  printf '{}' | bash "$HOOK"
}

add_item() {
  bash "$SCHEDULER" add "$1" "concept-$1" "answer-$1" "source-$1"
}

# ---------- normal ----------

@test "2 due items: prints one line containing the count and the tutor skill name" {
  run add_item item-1
  [ "$status" -eq 0 ]
  run add_item item-2
  [ "$status" -eq 0 ]

  run run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"/memory-loop:tutor"* ]]
}

# ---------- error ----------

@test "scheduler script absent: silent exit 0" {
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/empty-plugin-root"
  mkdir -p "$CLAUDE_PLUGIN_ROOT"

  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed stdin: silent exit 0, no crash or hang" {
  run bash -c 'printf "{oops" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- boundary ----------

@test "0 due items: no output" {
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tutorEnabled=false: no output even with due items present" {
  run add_item item-1
  [ "$status" -eq 0 ]

  mkdir -p "$HOME/.claude/groundwork"
  jq -cn '{tutorEnabled: false}' > "$HOME/.claude/groundwork/memory-loop.json"

  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "non-numeric scheduler output (stub): silent exit 0" {
  export CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/stub-plugin-root"
  mkdir -p "$CLAUDE_PLUGIN_ROOT/skills/tutor/scripts"
  cat > "$CLAUDE_PLUGIN_ROOT/skills/tutor/scripts/tutor-schedule.sh" <<'EOF'
#!/usr/bin/env bash
echo "not-a-number"
EOF
  chmod +x "$CLAUDE_PLUGIN_ROOT/skills/tutor/scripts/tutor-schedule.sh"

  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
