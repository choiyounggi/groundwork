#!/usr/bin/env bats
# Tests for scripts/pin-pr-gate.sh — the two steps that keep back-to-back
# dev-loop releases from stranding pin PRs (issue #141).
#
#   superseded <vX.Y.Z>   stdin "<number> <branch>" lines -> PR numbers of
#                         older pin branches, one per line
#   wait-merged <pr> [attempts] [interval]
#                         0 merged, 3 closed unmerged, 4 still open after the
#                         last attempt, 2 usage error

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pin-pr-gate.sh"
  # The gh stub must be executable, so it lives in the repo's gitignored
  # .claude/tmp, never under /tmp; teardown removes it.
  STUB_DIR="${BATS_TEST_DIRNAME}/../.claude/tmp/pin-pr-gate-${BATS_TEST_NUMBER}"
  mkdir -p "$STUB_DIR"
}

teardown() {
  rm -r "${BATS_TEST_DIRNAME}/../.claude/tmp/pin-pr-gate-${BATS_TEST_NUMBER}"
}

# A gh double that answers `pr view` with the next line of $STUB_DIR/states,
# repeating the last line once they run out, and logs every call.
_stub_gh() {
  printf '%s\n' "$@" > "$STUB_DIR/states"
  cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
dir="$(dirname "$0")"
echo "$*" >> "$dir/calls"
n=$(wc -l < "$dir/calls")
total=$(wc -l < "$dir/states")
[ "$n" -gt "$total" ] && n=$total
line=$(sed -n "${n}p" "$dir/states")
[ "$line" = "FAIL" ] && exit 1
echo "$line"
EOF
  chmod +x "$STUB_DIR/gh"
}

_calls() { wc -l < "$STUB_DIR/calls" | tr -d ' '; }

# --- superseded ------------------------------------------------------------------

@test "superseded: lists only pin branches older than the tag" {
  run bash "$SCRIPT" superseded v1.33.18 <<'EOF'
120 chore/pin-dev-loop-v1.33.3
138 chore/pin-dev-loop-v1.33.17
139 chore/pin-dev-loop-v1.33.18
140 chore/pin-dev-loop-v1.33.19
117 feat/memory-loop-context-diet
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '120\n138')" ]
}

@test "superseded: compares versions numerically, not as text" {
  # As text, v1.33.9 sorts after v1.33.10; as a version it is older.
  run bash "$SCRIPT" superseded v1.33.10 <<'EOF'
5 chore/pin-dev-loop-v1.33.9
6 chore/pin-dev-loop-v1.4.0
7 chore/pin-dev-loop-v2.0.0
8 chore/pin-dev-loop-v1.33.10
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '5\n6')" ]
}

@test "superseded: empty input prints nothing and succeeds (boundary)" {
  run bash "$SCRIPT" superseded v1.0.0 < /dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "superseded: a malformed pin branch is skipped, never closed" {
  run bash "$SCRIPT" superseded v1.33.18 <<'EOF'
9 chore/pin-dev-loop-main
10 chore/pin-dev-loop-v1.33
11 chore/pin-dev-loop-v1.33.1-rc1
12 chore/pin-dev-loop-v1.33.1
EOF
  [ "$status" -eq 0 ]
  [ "$output" = "12" ]
}

@test "superseded: a tag that is not vX.Y.Z is a usage error" {
  run bash "$SCRIPT" superseded 1.33.18 < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a vX.Y.Z release tag"* ]]
}

# --- wait-merged -----------------------------------------------------------------

@test "wait-merged: returns 0 once the PR reads MERGED" {
  _stub_gh OPEN OPEN MERGED
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 5 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"merged: #138"* ]]
  [ "$(_calls)" -eq 3 ]
  grep -q "pr view 138 --json state --jq .state" "$STUB_DIR/calls"
}

@test "wait-merged: a PR closed without merging exits 3 at once" {
  _stub_gh OPEN CLOSED MERGED
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 5 0
  [ "$status" -eq 3 ]
  [[ "$output" == *"closed without merging"* ]]
  [ "$(_calls)" -eq 2 ]
}

@test "wait-merged: still open after the last attempt exits 4 (the stranded-PR case)" {
  _stub_gh OPEN
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 3 0
  [ "$status" -eq 4 ]
  [[ "$output" == *"still OPEN after 3 checks"* ]]
  [ "$(_calls)" -eq 3 ]
}

@test "wait-merged: a failed gh call is retried, not read as a verdict" {
  _stub_gh FAIL MERGED
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 5 0
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 2 ]
}

@test "wait-merged: one attempt checks exactly once (boundary)" {
  _stub_gh MERGED
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 1 0
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 1 ]
}

@test "wait-merged: zero or non-numeric attempts and PR numbers are usage errors" {
  _stub_gh MERGED
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 0 0
  [ "$status" -eq 2 ]
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged abc
  [ "$status" -eq 2 ]
  run env PIN_GH="$STUB_DIR/gh" bash "$SCRIPT" wait-merged 138 5 x
  [ "$status" -eq 2 ]
  [ ! -f "$STUB_DIR/calls" ]
}

# --- usage -----------------------------------------------------------------------

@test "no subcommand or an unknown one is a usage error" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" merge 138
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
