#!/usr/bin/env bats
# Tests for hooks/memory-staleness-check.sh.
# Bidirectional by design: the check must speak when memory has actually
# drifted AND must stay silent otherwise — a session-start reminder that fires
# on healthy memory is the failure mode it exists to prevent.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/memory-staleness-check.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  CWD="$BATS_TEST_TMPDIR/proj"
  SLUG=$(printf '%s' "$CWD" | sed 's|[^a-zA-Z0-9]|-|g')
  MEM="$HOME/.claude/projects/$SLUG/memory"
  STATE="$HOME/.claude/groundwork/memory-loop"
  GW="$HOME/.claude/groundwork"
  mkdir -p "$MEM" "$STATE" "$GW" "$CWD"
  # A recent consolidate run, so only the case under test can fire.
  date +%Y-%m-%d > "$STATE/last-consolidate"
}

run_hook() {
  jq -cn --arg c "$CWD" '{cwd: $c}' | bash "$HOOK"
}

# $1 name, $2 frontmatter lines (may be empty), $3 body
mem() {
  { printf -- '---\nname: %s\nmetadata:\n' "${1%.md}"; [ -n "$2" ] && printf '%s\n' "$2"; printf -- '---\n\n%s\n' "$3"; } > "$MEM/$1"
}

index() { printf '# Memory index\n\n%s\n' "$1" > "$MEM/MEMORY.md"; }

@test "healthy memory is silent" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no memory directory at all is silent" {
  rm -rf "$MEM"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a long-tier memory past the review window is reported as re-verify" {
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"re-verify"* ]]
  [[ "$output" == *"old.md(2020-01-01)"* ]]
  [[ "$output" == *"tier: long"* ]]
}

@test "an untiered stale memory is routed to the remember gate, not consolidate" {
  mem "untiered.md" "  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [U](untiered.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"no tier"* ]]
  [[ "$output" == *"remember gate"* ]]
  [[ "$output" == *"untiered.md(2020-01-01)"* ]]
}

@test "a reviewed: date newer than modified: suppresses the report" {
  mem "checked.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z
  reviewed: $(date +%Y-%m-%d)" "verified today, content unchanged"
  index "- [C](checked.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "with no date fields at all the file mtime decides" {
  mem "nodate.md" "" "no frontmatter dates"
  index "- [N](nodate.md) — hook"
  touch -t 202001010000 "$MEM/nodate.md"
  # MEMORY.md must not look older than the file, or drift fires too.
  touch -t 202001010000 "$MEM/MEMORY.md"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"nodate.md(2020-01-01)"* ]]
}

@test "memoryReviewDays 0 disables the age check" {
  printf '{"memoryReviewDays": 0}' > "$GW/memory-loop.json"
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an index entry pointing at a missing file is reported" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook
- [Gone](gone.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"index points at missing files"* ]]
  [[ "$output" == *"gone.md"* ]]
}

@test "a memory file missing from the index is reported as an orphan" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  mem "lonely.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing from the index"* ]]
  [[ "$output" == *"lonely.md"* ]]
}

@test "a memory file newer than MEMORY.md is reported as index drift" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  touch -t 202401010000 "$MEM/MEMORY.md"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"index drift"* ]]
  [[ "$output" == *"1 memory file"* ]]
}

@test "an oversized index is reported with both numbers" {
  printf '{"memoryIndexMaxLines": 3}' > "$GW/memory-loop.json"
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  printf '# Memory index\n\n- [A](a.md) — hook\n- x\n- y\n' > "$MEM/MEMORY.md"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md is 5/3 lines"* ]]
}

@test "consolidate never run is reported; a recent run is not" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  rm -f "$STATE/last-consolidate"
  run run_hook
  [[ "$output" == *"consolidate: never run"* ]]

  date +%Y-%m-%d > "$STATE/last-consolidate"
  rm -f "$STATE/staleness-last-report"
  run run_hook
  [ -z "$output" ]
}

@test "an overdue consolidate run is reported with its date" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  printf '2020-01-01' > "$STATE/last-consolidate"
  run run_hook
  [[ "$output" == *"last run 2020-01-01"* ]]
}

@test "the cooldown silences a second run, and 0 disables the cooldown" {
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [ -n "$output" ]

  run run_hook
  [ -z "$output" ]

  printf '{"memoryCheckCooldownDays": 0}' > "$GW/memory-loop.json"
  run run_hook
  [[ "$output" == *"re-verify"* ]]
}

@test "repo config wins over global config" {
  printf '{"memoryReviewDays": 90}' > "$GW/memory-loop.json"
  mkdir -p "$CWD/.groundwork"
  printf '{"memoryReviewDays": 0}' > "$CWD/.groundwork/memory-loop.json"
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "archived memories and MEMORY.md itself are not treated as memories" {
  mkdir -p "$MEM/archived"
  printf -- '---\nname: gone\nmetadata:\n  tier: long\n  modified: 2020-01-01T00:00:00.000Z\n---\n' > "$MEM/archived/gone.md"
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "malformed stdin falls back to PWD and does not crash" {
  run bash -c "printf 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "empty stdin does not crash" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "the report names the reviewed: escape hatch with today's date" {
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [[ "$output" == *"reviewed: $(date +%Y-%m-%d)"* ]]
  [[ "$output" == *"writes only on confirmation"* ]]
}

# --- review findings: regression cases ----------------------------------------

@test "a modified: newer than reviewed: wins — an edit after a review is not stale" {
  # consolidate's own "partly wrong -> correct it, set modified" step never
  # touches reviewed:, so first-field-wins would flag a freshly edited file.
  mem "edited.md" "  tier: long
  reviewed: 2020-01-01
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "corrected recently"
  index "- [E](edited.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "both dates old: the later one is the one reported" {
  mem "both.md" "  tier: long
  reviewed: 2020-01-01
  modified: 2021-06-15T00:00:00.000Z" "old either way"
  index "- [B](both.md) — hook"
  run run_hook
  [[ "$output" == *"both.md(2021-06-15)"* ]]
  [[ "$output" != *"2020-01-01"* ]]
}

@test "an orphan is not hidden by a longer filename in the index" {
  # `auth.md` is orphaned, but the index mentions `oauth.md`; a substring test
  # would match and silently drop the orphan.
  mem "auth.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  mem "oauth.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [OAuth](oauth.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"missing from the index"* ]]
  [[ "$output" == *"auth.md"* ]]
}

@test "tier: short with an absolute expires is left to the expiry sweep" {
  mem "shortabs.md" "  tier: short
  expires: 2020-03-01
  modified: 2020-01-01T00:00:00.000Z" "sweep owns this"
  index "- [S](shortabs.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tier: short with a conditional expiry gets its own bucket, not the consolidate one" {
  mem "cond.md" "  tier: short
  expires_when: \"after the release ships\"
  modified: 2020-01-01T00:00:00.000Z" "waiting on an event"
  index "- [C](cond.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"no absolute expiry"* ]]
  [[ "$output" == *"cond.md(2020-01-01)"* ]]
  [[ "$output" != *"consolidate may act"* ]]
}

@test "tier: long is labelled as the bucket consolidate may act on" {
  mem "long.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [L](long.md) — hook"
  run run_hook
  [[ "$output" == *"tier: long — consolidate may act"* ]]
}

@test "an unrecognized tier value is treated as untiered, not as consolidate-able" {
  mem "weird.md" "  tier: medium
  modified: 2020-01-01T00:00:00.000Z" "typo tier"
  index "- [W](weird.md) — hook"
  run run_hook
  [[ "$output" == *"no tier"* ]]
  [[ "$output" == *"weird.md(2020-01-01)"* ]]
}

@test "quoted frontmatter dates parse the same as bare ones" {
  mem "quoted.md" "  tier: long
  modified: \"2020-01-01T00:00:00.000Z\"" "quoted date"
  index "- [Q](quoted.md) — hook"
  run run_hook
  [[ "$output" == *"quoted.md(2020-01-01)"* ]]
}
