#!/usr/bin/env bats
# Tests for scripts/auto-tag.sh — detects which bundled plugins need a
# release tag, which are already released, and which hit a tag-namespace
# collision (the v1.3.0 incident, caught at bump time instead of tag time).
#
# Content assertions use `grep -qF` rather than mid-test `[[ … ]]`: bats runs
# under bash 3.2 on macOS, where a false `[[ ]]` outside the test's last line
# does not fail the test (set -e is suppressed there pre-bash-4).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/auto-tag.sh"
}

# Builds a real git repo at $FIXTURE (git init + a commit). Unlike
# check-versions.sh, auto-tag.sh shells out to `git rev-parse`/`git show`/
# tags, so files on disk alone are not enough — it needs actual git history.
init_fixture() {
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE/.claude-plugin"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email "test@example.com"
  git -C "$FIXTURE" config user.name "Test"
}

# write_plugin <plugin-dir> <version> — writes a plugin.json at
# $FIXTURE/<plugin-dir>/.claude-plugin/plugin.json
write_plugin() {
  mkdir -p "$FIXTURE/$1/.claude-plugin"
  jq -n --arg v "$2" '{name: "pluginA", version: $v}' > "$FIXTURE/$1/.claude-plugin/plugin.json"
}

# commit_fixture <message> — stages and commits everything currently in $FIXTURE
commit_fixture() {
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -q -m "$1"
}

@test "normal: prints a need line when the release tag does not exist yet" {
  init_fixture
  jq -n '{plugins: [{name: "pluginA", source: "./plugins/pluginA"}]}' > "$FIXTURE/.claude-plugin/marketplace.json"
  write_plugin "plugins/pluginA" "1.0.0"
  commit_fixture "init"

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "need: v1.0.0 pluginA"
}

@test "normal: skips a plugin whose tag already exists at the same version" {
  init_fixture
  jq -n '{plugins: [{name: "pluginA", source: "./plugins/pluginA"}]}' > "$FIXTURE/.claude-plugin/marketplace.json"
  write_plugin "plugins/pluginA" "1.0.0"
  commit_fixture "init"
  git -C "$FIXTURE" tag v1.0.0

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip: v1.0.0 already released for pluginA"
}

@test "error: exit 1 COLLISION when the tag exists but that plugin's manifest there has a different version" {
  init_fixture
  jq -n '{plugins: [{name: "pluginA", source: "./plugins/pluginA"}]}' > "$FIXTURE/.claude-plugin/marketplace.json"
  # Simulate the v1.3.0 incident: tag v1.0.0 was created by some earlier
  # release while pluginA was still at 0.9.0 — the tag namespace is shared,
  # so pluginA later bumping to 1.0.0 collides with that existing tag.
  write_plugin "plugins/pluginA" "0.9.0"
  commit_fixture "old version, tag reused by another release"
  git -C "$FIXTURE" tag v1.0.0

  write_plugin "plugins/pluginA" "1.0.0"
  commit_fixture "bump to 1.0.0"

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "COLLISION"
  printf '%s\n' "$output" | grep -qF "v1.0.0"
  printf '%s\n' "$output" | grep -qF "pluginA"
  printf '%s\n' "$output" | grep -qF "0.9.0"
}

@test "boundary: a url-source entry is skipped, not needing a tag" {
  init_fixture
  jq -n '{plugins: [{name: "remote", source: {source: "url", url: "https://example.com/repo.git"}}]}' > "$FIXTURE/.claude-plugin/marketplace.json"
  commit_fixture "init"

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip: remote (non-local source"
}

@test "error: a marketplace with no .plugins array exits 2 naming the file" {
  init_fixture
  jq -n '{noplugins: true}' > "$FIXTURE/.claude-plugin/marketplace.json"
  commit_fixture "init"

  run "$SCRIPT" "$FIXTURE"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "marketplace.json"
}
