#!/usr/bin/env bats
# Tests for scripts/check-workflows.sh — catch a workflow that GitHub would
# register with no triggers (unparseable YAML) or that would die at runtime
# (a run block that is not valid bash).

setup() {
  command -v ruby >/dev/null || skip "ruby is required to parse workflow YAML"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-workflows.sh"
  ROOT="${BATS_TEST_TMPDIR}/repo"
  WF="${ROOT}/.github/workflows"
  mkdir -p "$WF"
}

_good_workflow() {
  cat > "${WF}/good.yml" <<'EOF'
name: good
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "hello"
          if [ -n "$HOME" ]; then echo "home"; fi
EOF
}

# --- the real repo --------------------------------------------------------------

@test "every workflow in this repo parses and has triggers" {
  run bash "$SCRIPT" "${BATS_TEST_DIRNAME}/.."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: sync-dev-loop-pin.yml"* ]]
}

# --- happy path -----------------------------------------------------------------

@test "a well-formed workflow passes" {
  _good_workflow
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: good.yml"* ]]
}

# --- the failure that actually happened -----------------------------------------

@test "a column-0 continuation inside a run block is caught" {
  # This is the sync-dev-loop-pin.yml bug: the unindented line ends the block
  # scalar, so the file is unparseable and GitHub registers NO triggers.
  cat > "${WF}/broken.yml" <<'EOF'
name: broken
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          git commit -m "subject line

body line at column zero"
EOF
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.yml"* ]]
}

@test "a workflow with no triggers is caught" {
  cat > "${WF}/no-on.yml" <<'EOF'
name: no triggers
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no triggers"* ]]
}

@test "an empty on: block is caught" {
  cat > "${WF}/empty-on.yml" <<'EOF'
name: empty triggers
on: {}
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no triggers"* ]]
}

@test "a workflow with no name is caught" {
  cat > "${WF}/no-name.yml" <<'EOF'
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no top-level name"* ]]
}

@test "a run block that is not valid bash is caught" {
  cat > "${WF}/bad-bash.yml" <<'EOF'
name: bad bash
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [ -n "$HOME" ]; then
            echo "unterminated
EOF
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid bash"* ]]
}

@test "one broken file fails the run even when another is fine" {
  _good_workflow
  printf 'name: x\non:\n  push:\njobs:\n  a:\n    steps:\n      - run: |\n          echo "x\n\nunindented"\n' > "${WF}/broken.yml"
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 1 ]
}

# --- boundaries ------------------------------------------------------------------

@test "a missing workflow directory is an error, not a silent pass" {
  run bash "$SCRIPT" "${BATS_TEST_TMPDIR}/nowhere"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no workflow directory"* ]]
}

@test "an empty workflow directory is an error, not a silent pass" {
  run bash "$SCRIPT" "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no workflow files"* ]]
}

@test "usage error with too many arguments" {
  _good_workflow
  run bash "$SCRIPT" "$ROOT" extra
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
