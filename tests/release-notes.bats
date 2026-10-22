#!/usr/bin/env bats
# Tests for scripts/release-notes.sh — notes for one plugin's tag, listing
# only commits under that plugin since ITS previous tag, even though every
# plugin shares one `v*` tag namespace.
#
# Content assertions use `grep -qF` rather than mid-test `[[ … ]]`: bats runs
# under bash 3.2 on macOS, where a false `[[ ]]` outside the test's last line
# does not fail the test (set -e is suppressed there pre-bash-4).

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/release-notes.sh"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email "test@example.com"
  git -C "$FIXTURE" config user.name "Test"
  unset GITHUB_REPOSITORY
}

# lacks <text> — fails when $output contains <text>. A bare `! grep` does not
# fail a bats test (bash exempts `!` pipelines from set -e), so it never caught
# anything.
lacks() {
  if printf '%s\n' "$output" | grep -qF "$1"; then
    echo "unexpected in output: $1"
    return 1
  fi
}

# bump <plugin-dir> <version> <subject> — writes the plugin's manifest and commits
bump() {
  mkdir -p "$FIXTURE/$1/.claude-plugin"
  jq -n --arg v "$2" '{name: "p", version: $v}' > "$FIXTURE/$1/.claude-plugin/plugin.json"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -q -m "$3"
}

# touch_path <path> <subject> — commits a change to a file outside any manifest
touch_path() {
  mkdir -p "$FIXTURE/$(dirname "$1")"
  echo "$2" >> "$FIXTURE/$1"
  git -C "$FIXTURE" add -A
  git -C "$FIXTURE" commit -q -m "$2"
}

@test "normal: lists only this plugin's commits since its own tag, skipping another plugin's newer tag" {
  bump plugins/a 1.0.0 "feat(a): first (#1)"
  git -C "$FIXTURE" tag v1.0.0
  # Another plugin's tag that sorts above v1.0.0 and is newer: GitHub's
  # --generate-notes would compare against it.
  bump plugins/b 1.0.9 "feat(b): other plugin (#2)"
  git -C "$FIXTURE" tag v1.0.9
  touch_path .claude-plugin/marketplace.json "feat(marketplace): bump pin (#3)"
  touch_path plugins/a/README.md "docs(a): explain (#4)"
  bump plugins/a 1.1.0 "feat(a): second (#5)"
  git -C "$FIXTURE" tag v1.1.0

  GITHUB_REPOSITORY=o/r run "$SCRIPT" v1.1.0 plugins/a "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "* feat(a): second (#5)"
  printf '%s\n' "$output" | grep -qxF "* docs(a): explain (#4)"
  lacks "(#3)"
  lacks "(#2)"
  lacks "(#1)"
  printf '%s\n' "$output" | grep -qxF "**Full Changelog**: https://github.com/o/r/compare/v1.0.0...v1.1.0"
}

@test "boundary: a first release, given as ./dir/, lists the plugin's whole history and links its commits" {
  bump plugins/b 0.3.0 "feat(b): other plugin (#2)"
  git -C "$FIXTURE" tag v0.3.0
  bump plugins/a 0.1.1 "feat(a): new plugin (#7)"
  git -C "$FIXTURE" tag v0.1.1

  GITHUB_REPOSITORY=o/r run "$SCRIPT" v0.1.1 ./plugins/a/ "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "* feat(a): new plugin (#7)"
  lacks "(#2)"
  printf '%s\n' "$output" | grep -qxF "**Full Changelog**: https://github.com/o/r/commits/v0.1.1/plugins/a"
}

@test "normal: no Full Changelog line without GITHUB_REPOSITORY" {
  bump plugins/a 1.0.0 "feat(a): first (#1)"
  git -C "$FIXTURE" tag v1.0.0

  run "$SCRIPT" v1.0.0 plugins/a "$FIXTURE"
  [ "$status" -eq 0 ]
  lacks "Full Changelog"
  printf '%s\n' "$output" | grep -qxF "* feat(a): first (#1)"
}

@test "error: exit 2 when the tag does not exist" {
  bump plugins/a 1.0.0 "feat(a): first (#1)"

  run "$SCRIPT" v9.9.9 plugins/a "$FIXTURE"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "tag not found: v9.9.9"
}

@test "error: exit 2 when the directory is not a plugin at that tag" {
  bump plugins/a 1.0.0 "feat(a): first (#1)"
  git -C "$FIXTURE" tag v1.0.0

  run "$SCRIPT" v1.0.0 plugins/missing "$FIXTURE"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "no plugins/missing/.claude-plugin/plugin.json at v1.0.0"
}

@test "error: exit 2 on missing or empty arguments" {
  run "$SCRIPT" v1.0.0
  [ "$status" -eq 2 ]
  run "$SCRIPT" "" plugins/a
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "usage:"
}

@test "boundary: a tag on a branch not merged into the release is not its previous tag" {
  bump plugins/a 1.0.0 "feat(a): first (#1)"
  git -C "$FIXTURE" tag v1.0.0
  git -C "$FIXTURE" checkout -q -b side
  bump plugins/a 1.0.5 "feat(a): side experiment (#2)"
  git -C "$FIXTURE" tag v1.0.5
  git -C "$FIXTURE" checkout -q -
  bump plugins/a 1.1.0 "feat(a): second (#3)"
  git -C "$FIXTURE" tag v1.1.0

  GITHUB_REPOSITORY=o/r run "$SCRIPT" v1.1.0 plugins/a "$FIXTURE"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "* feat(a): second (#3)"
  lacks "(#2)"
  printf '%s\n' "$output" | grep -qxF "**Full Changelog**: https://github.com/o/r/compare/v1.0.0...v1.1.0"
}
