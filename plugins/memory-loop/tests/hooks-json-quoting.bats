#!/usr/bin/env bats
# Regression guard: every hooks/hooks.json command must quote the
# ${CLAUDE_PLUGIN_ROOT} expansion. A plugin root containing a space (e.g. a
# CLAUDE_CONFIG_DIR under ~/Library/Application Support/...) otherwise splits
# into two words, the hook never runs, and the guard it carries is silently off.
# Assertions are simple commands ([ ], grep -q) because a mid-test [[ ]] is
# ignored by macOS bash 3.2.

setup() {
  HOOKS_JSON="${BATS_TEST_DIRNAME}/../hooks/hooks.json"
}

# Print every "command" value in the manifest FILE, one per line.
_commands() {
  jq -r '.. | objects | select(has("command")) | .command' "$1"
}

# Print the commands in FILE that expand CLAUDE_PLUGIN_ROOT without a
# preceding double quote; prints nothing (exit 0) when there are none.
_unquoted() {
  _commands "$1" | grep -E '(^|[^"])\$\{?CLAUDE_PLUGIN_ROOT' || true
}

# Put a stub named like the hook RAW points at under a root whose path has a
# space, then run RAW through a shell with CLAUDE_PLUGIN_ROOT set to that root —
# the way the harness runs a hook command, so the shell's own word-splitting is
# what is under test. The stub stands in for the real hook so this checks the
# command's quoting, not the hook. Sets $status and $output like bats `run`.
_run_with_space_root() {
  local raw="$1" root="$BATS_TEST_TMPDIR/root with space" name
  name="${raw##*hooks/}"
  name="${name%\"}"
  mkdir -p "$root/hooks"
  printf '#!/usr/bin/env bash\necho "stub-ran:%s"\n' "$name" > "$root/hooks/$name"
  status=0
  output=$(CLAUDE_PLUGIN_ROOT="$root" sh -c "$raw" 2>&1) || status=$?
}

@test "normal: hooks.json parses and declares exactly 7 hook commands" {
  run jq -e . "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  run _commands "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 7 ]
}

@test "normal: every hooks.json command has the quoted shape bash \"\${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh\"" {
  run _commands "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  bad=$(printf '%s\n' "$output" | grep -vE '^bash "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/[a-z-]+\.sh"$' || true)
  [ -z "$bad" ]
}

@test "normal: no hooks.json command expands CLAUDE_PLUGIN_ROOT unquoted" {
  run _unquoted "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "error: the unquoted detector flags a manifest with one unquoted command" {
  jq '.hooks.PreToolUse[0].hooks[0].command = "bash ${CLAUDE_PLUGIN_ROOT}/hooks/probe.sh"' "$HOOKS_JSON" > "$BATS_TEST_TMPDIR/hooks.json"
  run _unquoted "$BATS_TEST_TMPDIR/hooks.json"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/probe.sh'
}

@test "boundary: manifests with no CLAUDE_PLUGIN_ROOT mention or no commands are not flagged" {
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}' > "$BATS_TEST_TMPDIR/plain.json"
  printf '%s\n' '{}' > "$BATS_TEST_TMPDIR/empty.json"
  run _unquoted "$BATS_TEST_TMPDIR/plain.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run _commands "$BATS_TEST_TMPDIR/empty.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "smoke: every manifest command runs from a plugin root containing a space" {
  run _commands "$HOOKS_JSON"
  [ "$status" -eq 0 ]
  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    _run_with_space_root "$raw"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qF 'stub-ran:'
  done <<< "$output"
}

@test "error: the unquoted form fails from a plugin root containing a space" {
  _run_with_space_root 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/correction-signal.sh'
  [ "$status" -eq 127 ]
  printf '%s\n' "$output" | grep -qF 'No such file or directory'
}
