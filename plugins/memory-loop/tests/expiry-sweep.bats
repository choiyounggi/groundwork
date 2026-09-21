#!/usr/bin/env bats
# Tests for hooks/memory-expiry-sweep.sh.
# Bidirectional by design: lapsed short-tier files must be archived, and
# everything else (no tier, long tier, conditional expiry, MEMORY.md, the
# expiry day itself) must be provably left untouched.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/memory-expiry-sweep.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$HOME" "$PROJ"
  SLUG=$(printf '%s' "$PROJ" | sed 's|[^a-zA-Z0-9]|-|g')
  MEM="$HOME/.claude/projects/$SLUG/memory"
  mkdir -p "$MEM"
  TODAY=$(date +%Y-%m-%d)
}

# mem_file <dir> <name> <frontmatter line>...
mem_file() {
  local dir="$1" name="$2"
  shift 2
  { printf -- '---\n'; printf '%s\n' "$@"; printf -- '---\n\nbody\n'; } > "$dir/$name"
}

run_hook() {
  jq -cn --arg c "$PROJ" '{cwd: $c}' | bash "$HOOK"
}

@test "archives a lapsed short-tier memory and reports it" {
  mem_file "$MEM" "old-note.md" "tier: short" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ ! -e "$MEM/old-note.md" ]
  [ -e "$MEM/archived/old-note.md" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
  [[ "$output" == *"1 file(s) archived"* ]]
  [[ "$output" == *"$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md"* ]]
  DETAIL="$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md"
  [ -f "$DETAIL" ]
  grep -qF "old-note.md (expired 2000-01-01" "$DETAIL"
  grep -qF "moved to archived/" "$DETAIL"
}

@test "two files archived in one run: still one line, detail file lists both" {
  mem_file "$MEM" "first.md" "tier: short" "expires: 2000-01-01"
  mem_file "$MEM" "second.md" "tier: short" "expires: 2001-02-03"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/archived/first.md" ]
  [ -e "$MEM/archived/second.md" ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
  [[ "$output" == *"2 file(s) archived"* ]]
  [[ "$output" != *"first.md"* ]]
  DETAIL="$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md"
  grep -qF "first.md (expired 2000-01-01" "$DETAIL"
  grep -qF "second.md (expired 2001-02-03" "$DETAIL"
  grep -qF "MEMORY.md" "$DETAIL"
}

@test "state dir blocked by a regular file: still archives and exits 0" {
  mkdir -p "$HOME/.claude/groundwork"
  printf 'not a dir' > "$HOME/.claude/groundwork/memory-loop"
  mem_file "$MEM" "old-note.md" "tier: short" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ ! -e "$MEM/old-note.md" ]
  [ -e "$MEM/archived/old-note.md" ]
  [ -f "$HOME/.claude/groundwork/memory-loop" ]
}

@test "expiry date is exclusive: a file expiring today stays live" {
  mem_file "$MEM" "today.md" "tier: short" "expires: $TODAY"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/today.md" ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "long-tier files are never swept even with a past expires" {
  mem_file "$MEM" "keep.md" "tier: long" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/keep.md" ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "native files without a tier key are never touched" {
  mem_file "$MEM" "native.md" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/native.md" ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "conditional expires_when is never auto-archived" {
  mem_file "$MEM" "cond.md" "tier: short" 'expires_when: "after the release"'
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/cond.md" ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "MEMORY.md is always skipped" {
  mem_file "$MEM" "MEMORY.md" "tier: short" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$MEM/MEMORY.md" ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "empty stdin falls back to PWD as the project cwd" {
  mem_file "$MEM" "old.md" "tier: short" "expires: 2000-01-01"
  run bash -c 'cd "$1" && printf "" | bash "$2"' _ "$PROJ" "$HOOK"
  [ "$status" -eq 0 ]
  [ -e "$MEM/archived/old.md" ]
}

@test "missing memory dir exits 0 with no output" {
  rm -rf "$HOME/.claude/projects"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md" ]
}

@test "repo config wins over global config for extraMemoryDirs" {
  REPO_EXTRA="$BATS_TEST_TMPDIR/repo-extra"
  GLOBAL_EXTRA="$BATS_TEST_TMPDIR/global-extra"
  mkdir -p "$REPO_EXTRA" "$GLOBAL_EXTRA" "$HOME/.claude/groundwork" "$PROJ/.groundwork"
  jq -cn --arg d "$GLOBAL_EXTRA" '{extraMemoryDirs: [$d]}' \
    > "$HOME/.claude/groundwork/memory-loop.json"
  jq -cn --arg d "$REPO_EXTRA" '{extraMemoryDirs: [$d]}' \
    > "$PROJ/.groundwork/memory-loop.json"
  mem_file "$REPO_EXTRA" "repo-old.md" "tier: short" "expires: 2000-01-01"
  mem_file "$GLOBAL_EXTRA" "global-old.md" "tier: short" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$REPO_EXTRA/archived/repo-old.md" ]
  [ -e "$GLOBAL_EXTRA/global-old.md" ]
  [ ! -e "$GLOBAL_EXTRA/archived/global-old.md" ]
}

@test "extraMemoryDirs from the global config are swept too" {
  EXTRA="$BATS_TEST_TMPDIR/extra"
  mkdir -p "$EXTRA" "$HOME/.claude/groundwork"
  jq -cn --arg d "$EXTRA" '{extraMemoryDirs: [$d]}' \
    > "$HOME/.claude/groundwork/memory-loop.json"
  mem_file "$EXTRA" "extra-old.md" "tier: short" "expires: 2000-01-01"
  run run_hook
  [ "$status" -eq 0 ]
  [ -e "$EXTRA/archived/extra-old.md" ]
  grep -qF "extra-old.md" "$HOME/.claude/groundwork/memory-loop/expiry-sweep-last.md"
}
