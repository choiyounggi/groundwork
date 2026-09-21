#!/usr/bin/env bats
# Tests for hooks/hooks.json — the plugin's hook-registration manifest.
# Asserts the file's own shape (never runs any hook), plus a repo-wide sweep
# that the retired learning-nudge name is gone outside this file's own
# source, the one legitimate history mention, and the two "Upgrading from
# 1.x" README notes. See plans/t3/tasks/01-hooks-json-bats.md.

bats_require_minimum_version 1.5.0

setup() {
  PLUGIN_DIR="${BATS_TEST_DIRNAME}/.."
  HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
}

# nudge_hits — path:line pairs matching learning-nudge/nudgeInterval under
# PLUGIN_DIR. Verified 2026-09-22 against the real merged files: of the 3
# lines the brief's DoD names as legitimate history, only
# memory-staleness-check.sh:280 actually contains this pattern —
# correction-signal.sh:7 and memory-staleness-check.bats:370 say "nudge"/
# "the nudge", never "learning-nudge" or "nudgeInterval", so excluding
# them here would be a no-op and they are not listed (excluding a line
# that can never match is not wrong, but it is not accurate either — the
# brief's DoD line names them as ALLOWED leftovers, not as GUARANTEED
# ones). The two "Upgrading from 1.x" notes Task 05 adds
# (README.md/README.ko.md) DO contain a literal `nudgeInterval` and are
# excluded by CONTENT, not by path:line, so a later doc edit that
# reflows the paragraph and shifts its line number does not silently
# defeat this test.
nudge_hits() {
  grep -rn -i "learning-nudge\|nudgeInterval" "$PLUGIN_DIR" 2>/dev/null \
    | grep -v "${PLUGIN_DIR}/hooks/memory-staleness-check.sh:280:" \
    | grep -v "${PLUGIN_DIR}/tests/hooks-json.bats:" \
    | grep -v 'nudgeInterval` in your config is' \
    | grep -v 'nudgeInterval`은 이제'
}

# ---------- normal ----------

@test "hooks.json is valid JSON" {
  run jq empty "$HOOKS_JSON"
  [ "$status" -eq 0 ]
}

@test "hooks.json has no Stop key" {
  run jq -e '.hooks.Stop' "$HOOKS_JSON"
  [ "$status" -ne 0 ]
}

@test "UserPromptSubmit runs correction-signal.sh with no matcher" {
  run jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  [ "$output" = 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/correction-signal.sh' ]
  run jq -e '.hooks.UserPromptSubmit[0].matcher' "$HOOKS_JSON"
  [ "$status" -ne 0 ]
}

@test "every hooks/<x>.sh referenced in hooks.json exists" {
  run jq -r '[.hooks[][].hooks[].command] | .[]' "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    script="${cmd##*hooks/}"
    [ -f "${PLUGIN_DIR}/hooks/${script}" ]
  done <<< "$output"
}

@test "learning-nudge/nudgeInterval unreferenced under plugins/memory-loop outside documented history" {
  run nudge_hits
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ---------- error ----------

@test "a hooks.json referencing a nonexistent script fails the existence check" {
  BROKEN="$BATS_TEST_TMPDIR/hooks-broken.json"
  jq '.hooks.SessionStart[0].hooks[0].command = "bash ${CLAUDE_PLUGIN_ROOT}/hooks/does-not-exist.sh"' "$HOOKS_JSON" > "$BROKEN"
  run jq -r '[.hooks[][].hooks[].command] | .[]' "$BROKEN"
  [ "$status" -eq 0 ]
  found_missing=""
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    script="${cmd##*hooks/}"
    [ -f "${PLUGIN_DIR}/hooks/${script}" ] || found_missing=1
  done <<< "$output"
  [ -n "$found_missing" ]
}

# ---------- boundary ----------

@test "an empty hooks object is valid JSON, has no Stop key, and needs no existence check" {
  EMPTY="$BATS_TEST_TMPDIR/hooks-empty.json"
  jq -n '{description: "no hooks registered", hooks: {}}' > "$EMPTY"
  run jq empty "$EMPTY"
  [ "$status" -eq 0 ]
  run jq -e '.hooks.Stop' "$EMPTY"
  [ "$status" -ne 0 ]
  run jq -r '[.hooks[][].hooks[].command] | .[]' "$EMPTY"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
