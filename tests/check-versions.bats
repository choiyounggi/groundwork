#!/usr/bin/env bats
# Tests for scripts/check-versions.sh — CI-enforced version consistency
# between marketplace.json and each local plugin's plugin.json.
#
# Content assertions use `grep -qF` rather than mid-test `[[ … ]]`: bats runs
# under bash 3.2 on macOS, where a false `[[ ]]` outside the test's last line
# does not fail the test (set -e is suppressed there pre-bash-4).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-versions.sh"
  REPO_ROOT="${BATS_TEST_DIRNAME}/.."
}

# Checks the dev-loop marketplace entry's git ref against its version field —
# an invariant check-versions.sh does not cover, since it skips non-local
# (object) sources entirely. Echoes "ok" or "mismatch: ref=<r> version=<v>".
check_devloop_ref_version_sync() {
  jq -r '
    (.plugins[] | select(.name == "dev-loop")) as $p
    | ($p.source.ref // "none") as $ref
    | ($p.version // "none") as $ver
    | if $ref == ("v" + $ver) then "ok"
      else "mismatch: ref=" + $ref + " version=" + $ver
      end
  ' "$1"
}

# Builds a minimal fixture repo tree at $FIXTURE with the given marketplace.json
# body (a jq filter producing the .plugins array).
make_fixture() {
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/.claude-plugin"
  jq -n "$1" > "$FIXTURE/.claude-plugin/marketplace.json"
}

@test "normal: real repo has every local plugin's version in sync" {
  run "$SCRIPT" "$REPO_ROOT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "ok: guardrails"
  printf '%s\n' "$output" | grep -qF "ok: memory-loop"
  printf '%s\n' "$output" | grep -qF "skip: dev-loop"
}

@test "error: a version mismatch exits 1 and names the plugin and both versions" {
  make_fixture '{plugins: [{name: "pluginA", source: "./plugins/pluginA", version: "2.0.0"}]}'
  mkdir -p "$FIXTURE/plugins/pluginA/.claude-plugin"
  jq -n '{version: "1.0.0"}' > "$FIXTURE/plugins/pluginA/.claude-plugin/plugin.json"

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "pluginA"
  printf '%s\n' "$output" | grep -qF "2.0.0"
  printf '%s\n' "$output" | grep -qF "1.0.0"
}

@test "boundary: a url-source entry is skipped, not failed" {
  make_fixture '{plugins: [{name: "remote", source: {source: "url", url: "https://example.com/repo.git"}}]}'

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip: remote"
}

@test "boundary: a local-source entry with no plugin.json exits 2" {
  make_fixture '{plugins: [{name: "pluginA", source: "./plugins/pluginA", version: "1.0.0"}]}'

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "pluginA"
}

@test "error: a marketplace with no .plugins array exits 2 naming the file" {
  make_fixture '{noplugins: true}'

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "marketplace.json"
}

@test "normal: dev-loop marketplace ref tag matches its version field" {
  run check_devloop_ref_version_sync "$REPO_ROOT/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "error: a dev-loop ref/version mismatch is detected, not silently accepted" {
  make_fixture '{plugins: [{name: "dev-loop", source: {source: "url", url: "https://example.com/x.git", ref: "v2.0.0"}, version: "1.0.0"}]}'

  run check_devloop_ref_version_sync "$FIXTURE/.claude-plugin/marketplace.json"
  [ "$status" -eq 0 ]
  [ "$output" = "mismatch: ref=v2.0.0 version=1.0.0" ]
}
