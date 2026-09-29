#!/usr/bin/env bats
# Tests for scripts/install-claude-imports.sh.
# The script owns exactly one managed block in ~/.claude/CLAUDE.md and must be
# safe to re-run: never duplicate a line, copy the user's own text byte for
# byte, always leave a backup, keep symlinks and modes, and fail loudly
# (nonzero, file untouched) when it cannot write.
#
# Content assertions use `grep`/`cmp` rather than mid-test `[[ … ]]`: bats runs
# under bash 3.2 on macOS, where a false `[[ ]]` outside the test's last line
# does not fail the test.

OPEN='<!-- groundwork:memory-loop imports — managed by /memory-loop:setup; edit the files, not these lines -->'
CLOSE='<!-- /groundwork:memory-loop -->'

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/install-claude-imports.sh"
  export HOME="$BATS_TEST_TMPDIR/ho me"      # a space: every path must be quoted
  CLAUDE_DIR="$HOME/.claude"
  TARGET="$CLAUDE_DIR/CLAUDE.md"
  mkdir -p "$CLAUDE_DIR"
}

teardown() {
  chmod u+w "$CLAUDE_DIR" 2>/dev/null || true
}

count_line() { grep -cxF -- "$1" "$TARGET"; }
backups()    { ls "$CLAUDE_DIR"/CLAUDE.md.bak-* 2>/dev/null | wc -l | tr -d ' '; }
line_no()    { grep -nxF -- "$1" "$2" | cut -d: -f1; }
# Octal mode, GNU (-c) or BSD (-f) stat. GNU is tried first: on GNU, `stat -f`
# means "file system status" and prints that instead of failing.
mode_of()    { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

@test "normal: no CLAUDE.md yet -> creates it with both imports, in order, inside one block" {
  rm -f "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$TARGET" ]
  [ "$(count_line '@groundwork/HABITS.md')" -eq 1 ]
  [ "$(count_line '@groundwork/OUTPUT.md')" -eq 1 ]
  o=$(line_no "$OPEN" "$TARGET"); h=$(line_no '@groundwork/HABITS.md' "$TARGET")
  u=$(line_no '@groundwork/OUTPUT.md' "$TARGET"); c=$(line_no "$CLOSE" "$TARGET")
  [ "$o" -lt "$h" ] && [ "$h" -lt "$u" ] && [ "$u" -lt "$c" ]
  [ "$(wc -l < "$TARGET" | tr -d ' ')" -eq 4 ]
  printf '%s\n' "$output" | grep -qF 'added to'
}

@test "idempotent: second run is byte-identical and writes no new backup" {
  bash "$SCRIPT" > /dev/null
  cp "$TARGET" "$BATS_TEST_TMPDIR/after1"; nb=$(backups)
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'ok: all memory-loop imports already present'
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/after1"
  [ "$(backups)" -eq "$nb" ]
}

@test "partial: a hand-added line is not duplicated, only the missing one is added, backup equals the original" {
  printf '## Mine\n\n- keep this\n\n@groundwork/HABITS.md\n' > "$TARGET"
  cp "$TARGET" "$BATS_TEST_TMPDIR/orig"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(count_line '@groundwork/HABITS.md')" -eq 1 ]
  [ "$(count_line '@groundwork/OUTPUT.md')" -eq 1 ]
  grep -qxF -- '- keep this' "$TARGET"
  [ "$(backups)" -eq 1 ]
  cmp -s "$CLAUDE_DIR"/CLAUDE.md.bak-* "$BATS_TEST_TMPDIR/orig"
}

@test "existing block: the user's text is copied byte for byte and the import lands before CLOSE" {
  # Every hazard for a bash read/printf loop: leading whitespace, trailing
  # backslash, printf directives, blank lines, and a CLOSE that is the last
  # line with no trailing newline.
  printf '  indented\nback\\\n%%s %%d \\n literal\n\n%s\n@groundwork/HABITS.md\n%s' "$OPEN" "$CLOSE" > "$TARGET"
  printf '  indented\nback\\\n%%s %%d \\n literal\n\n%s\n@groundwork/HABITS.md\n@groundwork/OUTPUT.md\n%s\n' "$OPEN" "$CLOSE" > "$BATS_TEST_TMPDIR/expected"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  cmp "$TARGET" "$BATS_TEST_TMPDIR/expected"
}

@test "existing block: insertion goes inside the block, not after the user's trailing section" {
  bash "$SCRIPT" > /dev/null
  sed -i.orig '/@groundwork\/OUTPUT.md/d' "$TARGET" && rm -f "$TARGET.orig"
  printf '\n## After the block\n' >> "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(count_line '@groundwork/OUTPUT.md')" -eq 1 ]
  [ "$(grep -c 'groundwork:memory-loop' "$TARGET")" -eq 2 ]
  u=$(line_no '@groundwork/OUTPUT.md' "$TARGET"); c=$(line_no "$CLOSE" "$TARGET"); a=$(line_no '## After the block' "$TARGET")
  [ "$u" -lt "$c" ] && [ "$c" -lt "$a" ]
}

@test "symlink: the link survives and the real file gets the block" {
  mkdir -p "$BATS_TEST_TMPDIR/dotfiles"
  printf '# dotfiles copy\n' > "$BATS_TEST_TMPDIR/dotfiles/claude.md"
  ln -s "$BATS_TEST_TMPDIR/dotfiles/claude.md" "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -L "$TARGET" ]
  grep -qxF -- '@groundwork/OUTPUT.md' "$BATS_TEST_TMPDIR/dotfiles/claude.md"
  grep -qxF -- '# dotfiles copy' "$BATS_TEST_TMPDIR/dotfiles/claude.md"
  ls "$BATS_TEST_TMPDIR"/dotfiles/claude.md.bak-* > /dev/null
}

@test "mode: a 600 file stays 600" {
  printf 'private\n' > "$TARGET"; chmod 600 "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$TARGET")" = "600" ]
}

@test "crlf: a CRLF file with the block gets the missing import inside it, no second block, CRs kept" {
  printf 'mine\r\n%s\r\n@groundwork/HABITS.md\r\n%s\r\n' "$OPEN" "$CLOSE" > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'groundwork:memory-loop' "$TARGET")" -eq 2 ]
  [ "$(count_line '@groundwork/OUTPUT.md')" -eq 1 ]
  [ "$(grep -c $'\r$' "$TARGET")" -eq 4 ]
  u=$(line_no '@groundwork/OUTPUT.md' "$TARGET"); c=$(grep -n 'groundwork:memory-loop -->' "$TARGET" | cut -d: -f1)
  [ "$u" -lt "$c" ]
}

@test "boundary: last line without a trailing newline is not glued to the block" {
  printf 'last line no newline' > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF -- 'last line no newline' "$TARGET"
  [ "$(count_line '@groundwork/HABITS.md')" -eq 1 ]
}

@test "boundary: empty CLAUDE.md gets just the block, no leading blank line, no empty backup" {
  : > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(head -c 4 "$TARGET")" = "<!--" ]
  [ "$(backups)" -eq 0 ]
}

@test "error: OPEN marker without CLOSE -> exit 1, file untouched" {
  printf 'mine\n%s\n@groundwork/HABITS.md\n' "$OPEN" > "$TARGET"
  cp "$TARGET" "$BATS_TEST_TMPDIR/orig"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'no closing marker'
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/orig"
  [ "$(backups)" -eq 0 ]
}

@test "error: CLAUDE.md is a directory -> exit 1" {
  rm -f "$TARGET"; mkdir "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'is a directory'
}

@test "error: unwritable ~/.claude -> nonzero exit, file untouched, no temp file left" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory write bits"
  printf '@nothing\n' > "$TARGET"
  chmod a-w "$CLAUDE_DIR"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF 'install-claude-imports:'
  [ "$(cat "$TARGET")" = "@nothing" ]
  [ -z "$(ls "$CLAUDE_DIR"/CLAUDE.md.tmp.* 2>/dev/null)" ]
}
