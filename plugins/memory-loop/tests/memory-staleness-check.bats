#!/usr/bin/env bats
# Tests for hooks/memory-staleness-check.sh.
# Bidirectional by design: the check must speak when memory has actually
# drifted AND must stay silent otherwise — a session-start reminder that fires
# on healthy memory is the failure mode it exists to prevent.

bats_require_minimum_version 1.5.0

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
  DETAIL="$STATE/staleness-last-detail.md"
}

# The report is one stdout line; the per-bucket text lives in $DETAIL.
one_line() { [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]; }
in_detail() { grep -qF -- "$1" "$DETAIL"; }
# A function (not a bare `! grep`) so a match fails the test under bats' set -e.
not_in_detail() { ! grep -qF -- "$1" "$DETAIL"; }

run_hook() {
  jq -cn --arg c "$CWD" '{cwd: $c}' | bash "$HOOK"
}

# Tests below chmod dirs read-only; give write back so bats can clean up.
teardown() {
  chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || true
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
  [ ! -e "$DETAIL" ]
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
  one_line
  [[ "$output" == "memory upkeep: re-verify — details: $DETAIL; run \"/memory-loop:consolidate\"." ]]
  in_detail "old.md(2020-01-01)"
  in_detail "tier: long"
}

@test "an untiered stale memory is routed to the remember gate, not consolidate" {
  mem "untiered.md" "  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [U](untiered.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [[ "$output" == *"re-verify"* ]]
  in_detail "no tier"
  in_detail "remember gate"
  in_detail "untiered.md(2020-01-01)"
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
  one_line
  in_detail "nodate.md(2020-01-01)"
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
  one_line
  [[ "$output" == *"memory upkeep: broken links — "* ]]
  in_detail "index points at missing files"
  in_detail "gone.md"
}

@test "a memory file missing from the index is reported as an orphan" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  mem "lonely.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [[ "$output" == *"memory upkeep: orphans — "* ]]
  in_detail "missing from the index"
  in_detail "lonely.md"
}

@test "a memory file newer than MEMORY.md is reported as index drift" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  touch -t 202401010000 "$MEM/MEMORY.md"
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [[ "$output" == *"memory upkeep: index drift — "* ]]
  in_detail "index drift: 1 memory file"
}

@test "an oversized index is reported with both numbers" {
  printf '{"memoryIndexMaxLines": 3}' > "$GW/memory-loop.json"
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  printf '# Memory index\n\n- [A](a.md) — hook\n- x\n- y\n' > "$MEM/MEMORY.md"
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [[ "$output" == *"memory upkeep: oversized index — "* ]]
  in_detail "MEMORY.md is 5/3 lines"
}

@test "consolidate never run is reported; a recent run is not" {
  mem "a.md" "  tier: long
  modified: $(date +%Y-%m-%d)T00:00:00.000Z" "fresh"
  index "- [A](a.md) — hook"
  rm -f "$STATE/last-consolidate"
  run run_hook
  one_line
  [[ "$output" == *"memory upkeep: consolidate overdue — "* ]]
  in_detail "consolidate: never run"

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
  one_line
  [[ "$output" == *"consolidate overdue"* ]]
  in_detail "consolidate: last run 2020-01-01"
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
  one_line
  [[ "$output" == *"$DETAIL"* ]]
  in_detail "reviewed: $(date +%Y-%m-%d)"
  in_detail "writes only on confirmation"
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
  one_line
  in_detail "both.md(2021-06-15)"
  not_in_detail "2020-01-01"
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
  one_line
  [[ "$output" == *"orphans"* ]]
  in_detail "missing from the index: auth.md"
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
  one_line
  in_detail "no absolute expiry"
  in_detail "cond.md(2020-01-01)"
  not_in_detail "consolidate may act"
}

@test "tier: long is labelled as the bucket consolidate may act on" {
  mem "long.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [L](long.md) — hook"
  run run_hook
  one_line
  in_detail "tier: long — consolidate may act"
}

@test "an unrecognized tier value is treated as untiered, not as consolidate-able" {
  mem "weird.md" "  tier: medium
  modified: 2020-01-01T00:00:00.000Z" "typo tier"
  index "- [W](weird.md) — hook"
  run run_hook
  one_line
  in_detail "no tier"
  in_detail "weird.md(2020-01-01)"
}

@test "quoted frontmatter dates parse the same as bare ones" {
  mem "quoted.md" "  tier: long
  modified: \"2020-01-01T00:00:00.000Z\"" "quoted date"
  index "- [Q](quoted.md) — hook"
  run run_hook
  one_line
  in_detail "quoted.md(2020-01-01)"
}

# --- one-line report ------------------------------------------------------------

@test "two buckets firing together share one line, comma-joined in fixed order" {
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook
- [Gone](gone.md) — hook"
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [ "$output" = "memory upkeep: re-verify, broken links — details: $DETAIL; run \"/memory-loop:consolidate\"." ]
  in_detail "old.md(2020-01-01)"
  in_detail "index points at missing files: gone.md"
  [ "$(cat "$STATE/staleness-last-report")" = "$(date +%Y-%m-%d)" ]
}

@test "the cooldown also silences the consolidate-overdue bucket" {
  # The cooldown no longer exits the script early; the overdue check must
  # still honour it on its own.
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
  run run_hook
  [ -n "$output" ]

  rm -f "$STATE/last-consolidate"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- habit file budget / rule cap / split threshold (relocated from the nudge) --

# habits_file <bytes> <rules> [path] — exactly <bytes> bytes, <rules> of them
# lines matching '^- \*\*', the rest non-rule filler.
habits_file() {
  local bytes="$1" rules="$2" f="${3:-$GW/HABITS.md}" i=0 have
  mkdir -p "$(dirname "$f")"
  : > "$f"
  while [ "$i" -lt "$rules" ]; do printf -- '- **r**\n' >> "$f"; i=$((i + 1)); done
  have=$(wc -c < "$f" | tr -d ' ')
  [ "$have" -le "$bytes" ]
  head -c $((bytes - have)) /dev/zero | tr '\0' 'x' >> "$f"
  [ "$(wc -c < "$f" | tr -d ' ')" = "$bytes" ]
}

small_limits() {
  printf '{"habitsBudgetBytes": 100, "habitsMaxRules": 3, "habitsSplitWarnBytes": 200}' > "$GW/memory-loop.json"
}

stale_long_memory() {
  mem "old.md" "  tier: long
  modified: 2020-01-01T00:00:00.000Z" "ancient"
  index "- [Old](old.md) — hook"
}

days_back() { date -v-"$1"d +%Y-%m-%d 2>/dev/null || date -d "$1 days ago" +%Y-%m-%d; }

@test "habits: one byte over budget is reported on the one line, guidance in the detail file" {
  small_limits
  habits_file 101 1
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [ "$output" = "memory upkeep: habits over budget — details: $DETAIL; run \"/memory-loop:consolidate\"." ]
  in_detail "HABITS.md is over budget: 101 bytes against a 100-byte budget."
  in_detail "Consolidate before you capture — the write guard will deny any edit that grows it."
  in_detail "HABITS-ARCHIVE.md"
  in_detail "name the existing rule it replaces"
}

@test "habits: one rule over the cap is reported as its own label" {
  small_limits
  habits_file 40 4
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [[ "$output" == "memory upkeep: habits over rule cap — "* ]]
  [[ "$output" != *"habits over budget"* ]]
  in_detail "HABITS.md is over budget: 4 rules against a cap of 3."
}

@test "habits: over budget and over the cap together name both in one sentence" {
  small_limits
  habits_file 150 4
  run run_hook
  one_line
  [[ "$output" == "memory upkeep: habits over budget, habits over rule cap — "* ]]
  in_detail "150 bytes against a 100-byte budget, and 4 rules against a cap of 3."
}

@test "habits: exactly at the byte budget and the rule cap is silent (-gt, not -ge)" {
  small_limits
  habits_file 100 3
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$DETAIL" ]
}

@test "habits: built-in defaults are 8000 bytes and 24 rules" {
  habits_file 8000 24
  run run_hook
  [ -z "$output" ]

  habits_file 8001 24
  run run_hook
  [[ "$output" == "memory upkeep: habits over budget — "* ]]
  in_detail "8001 bytes against a 8000-byte budget"

  habits_file 8000 25
  run run_hook
  [[ "$output" == "memory upkeep: habits over rule cap — "* ]]
  in_detail "25 rules against a cap of 24"
}

@test "habits: 0 disables each of the three checks" {
  printf '{"habitsBudgetBytes": 0, "habitsMaxRules": 0, "habitsSplitWarnBytes": 0}' > "$GW/memory-loop.json"
  habits_file 50000 40
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "habits: no habit file, or a non-numeric limit, fails open" {
  small_limits
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # A non-numeric setting falls back to the built-in default (8000), so a
  # 101-byte file is under budget again.
  printf '{"habitsBudgetBytes": "abc"}' > "$GW/memory-loop.json"
  habits_file 101 1
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "habits: past the split threshold with no cases file points at setup" {
  printf '{"habitsBudgetBytes": 0, "habitsSplitWarnBytes": 200}' > "$GW/memory-loop.json"
  habits_file 201 1
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [ "$output" = "memory upkeep: habits over split threshold — details: $DETAIL; run \"/memory-loop:consolidate\"." ]
  in_detail "HABITS.md is 201 bytes, past the 200-byte split threshold."
  in_detail "(<- background: ...)"
  in_detail "into a new HABITS-CASES.md beside it"
  in_detail "/memory-loop:setup"
  in_detail "Keep 🛑 hard lines inline"
}

@test "habits: past the split threshold with a cases file names that file instead" {
  printf '{"habitsBudgetBytes": 0, "habitsSplitWarnBytes": 200}' > "$GW/memory-loop.json"
  habits_file 201 1
  printf '# cases\n' > "$GW/HABITS-CASES.md"
  run run_hook
  one_line
  [[ "$output" == *"habits over split threshold"* ]]
  in_detail "into HABITS-CASES.md, leaving a [Cnn] pointer on each rule"
  not_in_detail "/memory-loop:setup"
}

@test "habits: habitsPath and habitsCasesPath from the repo config expand ~" {
  mkdir -p "$CWD/.groundwork"
  printf '{"habitsBudgetBytes": 0, "habitsSplitWarnBytes": 200, "habitsPath": "~/custom/MY-HABITS.md", "habitsCasesPath": "~/custom/MY-CASES.md"}' \
    > "$CWD/.groundwork/memory-loop.json"
  habits_file 201 1 "$HOME/custom/MY-HABITS.md"
  printf '# cases\n' > "$HOME/custom/MY-CASES.md"
  run run_hook
  one_line
  [[ "$output" == *"habits over split threshold"* ]]
  in_detail "MY-HABITS.md is 201 bytes"
  in_detail "into MY-CASES.md, leaving a [Cnn] pointer"
}

@test "habits: the cooldown silences upkeep buckets but never the habit bucket" {
  small_limits
  habits_file 101 1
  stale_long_memory
  run run_hook
  [[ "$output" == "memory upkeep: re-verify, habits over budget — "* ]]

  # Same day, inside the cooldown: re-verify is suppressed, the habit label is not.
  run run_hook
  [ "$status" -eq 0 ]
  one_line
  [ "$output" = "memory upkeep: habits over budget — details: $DETAIL; run \"/memory-loop:consolidate\"." ]
  not_in_detail "old.md"
}

@test "habits: once the cooldown has elapsed both kinds of bucket report together" {
  small_limits
  habits_file 101 1
  stale_long_memory
  days_back 8 > "$STATE/staleness-last-report"
  run run_hook
  one_line
  [[ "$output" == "memory upkeep: re-verify, habits over budget — "* ]]
  [ "$(cat "$STATE/staleness-last-report")" = "$(date +%Y-%m-%d)" ]
}

@test "habits: a habit-only report never writes the cooldown timestamp" {
  small_limits
  habits_file 101 1
  run run_hook
  [[ "$output" == *"habits over budget"* ]]
  [ ! -e "$STATE/staleness-last-report" ]

  printf '2020-01-01' > "$STATE/staleness-last-report"
  cp "$STATE/staleness-last-report" "$BATS_TEST_TMPDIR/report-before"
  run run_hook
  [[ "$output" == *"habits over budget"* ]]
  cmp "$BATS_TEST_TMPDIR/report-before" "$STATE/staleness-last-report"
}

@test "habits: each habit finding and the closing advice start their own detail line" {
  printf '{"habitsBudgetBytes": 100, "habitsSplitWarnBytes": 200}' > "$GW/memory-loop.json"
  habits_file 201 1
  run run_hook
  [[ "$output" == *"habits over budget, habits over split threshold"* ]]
  grep -q '^HABITS.md is over budget: 201 bytes' "$DETAIL"
  grep -q '^HABITS.md is 201 bytes, past the 200-byte split threshold' "$DETAIL"
  grep -q '^Do not act on this automatically' "$DETAIL"
}

# --- unwritable state: fail open, silently -------------------------------------

@test "unwritable groundwork dir: one line without a details clause, nothing on stderr" {
  # No state dir and no way to create it: the consolidate-overdue bucket fires
  # (no last-consolidate), and neither the detail file nor the cooldown
  # timestamp can be written.
  rm -rf "$STATE"
  chmod 555 "$GW"
  run --separate-stderr run_hook
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = 'memory upkeep: consolidate overdue; run "/memory-loop:consolidate".' ]
  [ ! -e "$STATE" ]
}

@test "read-only state dir: the detail write fails silently and the line drops the details clause" {
  stale_long_memory
  chmod 555 "$STATE"
  run --separate-stderr run_hook
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = 'memory upkeep: re-verify; run "/memory-loop:consolidate".' ]
  [ ! -e "$DETAIL" ]
  [ ! -e "$STATE/staleness-last-report" ]
}
