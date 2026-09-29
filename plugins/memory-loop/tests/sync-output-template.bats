#!/usr/bin/env bats
# Tests for scripts/sync-output-template.sh and hooks/output-template-sync.sh.
# The script owns exactly one managed block in the user's OUTPUT.md: it must
# seed a missing file, do nothing when the block is current, append the block
# to a file that has none (user text byte for byte), replace only the block
# when the template changed, always leave a backup on a write, keep symlinks
# and modes, and fail loudly (nonzero, file untouched) on a broken file or a
# missing template. The hook wraps it: one line on change, silence otherwise.
#
# Content assertions use `grep`/`cmp` rather than mid-test `[[ … ]]`: bats runs
# under bash 3.2 on macOS, where a false `[[ ]]` outside the test's last line
# does not fail the test.

bats_require_minimum_version 1.5.0

OPEN_PREFIX='<!-- groundwork:memory-loop output-style'
CLOSE='<!-- /groundwork:memory-loop output-style -->'

setup() {
  PLUGIN_DIR="${BATS_TEST_DIRNAME}/.."
  SCRIPT="${PLUGIN_DIR}/scripts/sync-output-template.sh"
  HOOK="${PLUGIN_DIR}/hooks/output-template-sync.sh"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
  export HOME="$BATS_TEST_TMPDIR/ho me"      # a space: every path must be quoted
  GW_DIR="$HOME/.claude/groundwork"
  TARGET="$GW_DIR/OUTPUT.md"
  mkdir -p "$GW_DIR"
  unset OUTPUT_TEMPLATE
}

count_line()   { grep -cxF -- "$1" "$TARGET"; }
count_prefix() { grep -c -- "^$1" "$TARGET"; }
backups()      { ls "$GW_DIR"/OUTPUT.md.bak-* 2>/dev/null | wc -l | tr -d ' '; }
line_no()      { grep -nxF -- "$1" "$2" | cut -d: -f1; }
mode_of()      { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
# The id stamped in the file's opening marker.
id_of()        { grep -- "^$OPEN_PREFIX" "$1" | head -1 | sed -n 's/.* template \([0-9][0-9]*\) .*/\1/p'; }
run_hook()     { printf '{}' | bash "$HOOK"; }

# A template whose block body differs from the real one, so an "outdated"
# state can be produced without hand-editing ids.
make_old_template() {
  OLD_TPL="$BATS_TEST_TMPDIR/old-template.md"
  printf '# header of old\n\n%s — managed block, template {{TEMPLATE_ID}} (memory-loop {{VERSION}}); x -->\nold rule one\nold rule two\n%s\n' "$OPEN_PREFIX" "$CLOSE" > "$OLD_TPL"
}

# ---------- normal ----------

@test "normal: no OUTPUT.md yet -> created from the template with one block and a numeric id" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == created:* ]]
  [ -f "$TARGET" ]
  [ "$(count_prefix "$OPEN_PREFIX")" -eq 1 ]
  [ "$(count_line "$CLOSE")" -eq 1 ]
  grep -q '^# OUTPUT' "$TARGET"
  grep -q 'Lead with the next action' "$TARGET"
  id=$(id_of "$TARGET")
  [ -n "$id" ]
  case "$id" in *[!0-9]*) false ;; esac
  [ "$(backups)" -eq 0 ]
}

@test "normal: current block -> ok:, file byte-identical, no backup" {
  bash "$SCRIPT" >/dev/null
  cp "$TARGET" "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == ok:* ]]
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/before"
  [ "$(backups)" -eq 0 ]
}

@test "normal: pre-2.3.0 file with no block -> user text kept byte for byte, block appended, backup written" {
  printf '# my rules\n\n- answer in Korean\n- keep tables\n' > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == merged:* ]]
  head -4 "$TARGET" > "$BATS_TEST_TMPDIR/head"
  printf '# my rules\n\n- answer in Korean\n- keep tables\n' | cmp -s - "$BATS_TEST_TMPDIR/head"
  [ "$(count_prefix "$OPEN_PREFIX")" -eq 1 ]
  [ "$(count_line "$CLOSE")" -eq 1 ]
  u=$(line_no '- keep tables' "$TARGET"); o=$(grep -n -- "^$OPEN_PREFIX" "$TARGET" | cut -d: -f1)
  [ "$u" -lt "$o" ]
  [ "$(backups)" -eq 1 ]
}

@test "normal: outdated block -> only the block is replaced; lines above and below survive" {
  make_old_template
  OUTPUT_TEMPLATE="$OLD_TPL" bash "$SCRIPT" >/dev/null
  printf 'trailing user note\n' >> "$TARGET"
  old_id=$(id_of "$TARGET")
  grep -q '^old rule one$' "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == updated:* ]]
  [[ "$output" == *"$old_id -> "* ]]
  new_id=$(id_of "$TARGET")
  [ "$new_id" != "$old_id" ]
  [ "$(grep -c '^old rule one$' "$TARGET")" -eq 0 ]
  grep -q 'Lead with the next action' "$TARGET"
  grep -q '^# header of old$' "$TARGET"
  grep -q '^trailing user note$' "$TARGET"
  [ "$(count_prefix "$OPEN_PREFIX")" -eq 1 ]
  [ "$(count_line "$CLOSE")" -eq 1 ]
  [ "$(backups)" -eq 1 ]
  # Second run is a no-op.
  run bash "$SCRIPT"
  [[ "$output" == ok:* ]]
  [ "$(backups)" -eq 1 ]
}

@test "normal: hook prints exactly one 'output style:' line on a merge and nothing when current" {
  printf 'mine\n' > "$TARGET"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '')" -eq 1 ]
  [[ "$output" == "output style: merged:"* ]]
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------- error ----------

@test "error: missing template -> exit 1, target untouched" {
  printf 'mine\n' > "$TARGET"
  run env OUTPUT_TEMPLATE="$BATS_TEST_TMPDIR/nope.md" bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"template not found"* ]]
  printf 'mine\n' | cmp -s - "$TARGET"
}

@test "error: template without a closing marker -> exit 1, target untouched" {
  printf '%s — x -->\nbody\n' "$OPEN_PREFIX" > "$BATS_TEST_TMPDIR/broken.md"
  printf 'mine\n' > "$TARGET"
  run env OUTPUT_TEMPLATE="$BATS_TEST_TMPDIR/broken.md" bash "$SCRIPT"
  [ "$status" -eq 1 ]
  printf 'mine\n' | cmp -s - "$TARGET"
}

@test "error: opening marker with no closing marker in the user's file -> exit 1, untouched, no backup" {
  printf 'mine\n%s — managed block, template 1 (memory-loop 0); x -->\nstale\n' "$OPEN_PREFIX" > "$TARGET"
  cp "$TARGET" "$BATS_TEST_TMPDIR/before"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no closing marker"* ]]
  cmp -s "$TARGET" "$BATS_TEST_TMPDIR/before"
  [ "$(backups)" -eq 0 ]
}

@test "error: the hook reports a failure in one line and still exits 0" {
  printf 'mine\n%s — managed block, template 1 (memory-loop 0); x -->\n' "$OPEN_PREFIX" > "$TARGET"
  run run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == "output style: template sync failed"* ]]
}

# ---------- boundary ----------

@test "boundary: empty OUTPUT.md -> block written, no leading blank lines, no backup of an empty file" {
  : > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == merged:* ]]
  [ "$(head -1 "$TARGET")" != "" ]
  grep -q -- "^$OPEN_PREFIX" "$TARGET"
  [ "$(backups)" -eq 0 ]
}

@test "boundary: CRLF user lines keep their CR; symlink stays a link; mode 600 kept" {
  REAL="$BATS_TEST_TMPDIR/dotfiles/output.md"
  mkdir -p "$(dirname "$REAL")"
  printf 'crlf line\r\n' > "$REAL"
  chmod 600 "$REAL"
  ln -s "$REAL" "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -L "$TARGET" ]
  [ "$(grep -c $'\r$' "$REAL")" -eq 1 ]
  grep -qxF -- "$CLOSE" "$REAL"
  [ "$(mode_of "$REAL")" = "600" ]
}

@test "normal: an unedited 2.2.0 seed is replaced whole — no duplicated rules, backup kept" {
  cp "${BATS_TEST_DIRNAME}/fixtures/OUTPUT-2.2.0.md" "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == replaced:* ]]
  [ "$(grep -c 'Lead with the next action' "$TARGET")" -eq 1 ]
  [ "$(count_prefix "$OPEN_PREFIX")" -eq 1 ]
  [ "$(backups)" -eq 1 ]
}

@test "normal: an unedited 2.1.0 seed is replaced whole too" {
  cp "${BATS_TEST_DIRNAME}/fixtures/OUTPUT-2.1.0.md" "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == replaced:* ]]
  [ "$(grep -c 'Explain like I' "$TARGET")" -eq 1 ]
}

@test "normal: the old-seed checksum list in the script matches the fixtures" {
  listed=$(sed -n 's/^OLD_SEEDS="\(.*\)"$/\1/p' "$SCRIPT")
  for f in "${BATS_TEST_DIRNAME}"/fixtures/OUTPUT-*.md; do
    sum=$(cksum < "$f" | cut -d' ' -f1)
    case " $listed " in *" $sum "*) ;; *) false ;; esac
  done
}

@test "normal: an edited 2.2.0 seed (one line changed) is kept and gets the block appended" {
  sed 's/^# OUTPUT — how to write$/# OUTPUT — mine/' "${BATS_TEST_DIRNAME}/fixtures/OUTPUT-2.2.0.md" > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == merged:* ]]
  grep -q '^# OUTPUT — mine$' "$TARGET"
  [ "$(grep -c 'Lead with the next action' "$TARGET")" -eq 2 ]
}

# ---------- error (review findings) ----------

@test "error: a dangling symlink target -> exit 1, the link is left in place" {
  ln -s "$BATS_TEST_TMPDIR/not/there.md" "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dangling symlink"* ]]
  [ -L "$TARGET" ]
  [ ! -e "$BATS_TEST_TMPDIR/not/there.md" ]
}

@test "boundary: markers quoted inside a code fence are the user's prose — kept, block appended after" {
  {
    printf '# notes\n\nExample of the marker:\n```\n'
    printf '%s — managed block, template EXAMPLE (memory-loop 9.9.9); x -->\nexample body text goes here\n%s\n' "$OPEN_PREFIX" "$CLOSE"
    printf '```\nEnd of example.\n'
  } > "$TARGET"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == merged:* ]]
  grep -q '^example body text goes here$' "$TARGET"
  grep -q '^End of example.$' "$TARGET"
  [ "$(count_line "$CLOSE")" -eq 2 ]
  # And a second run sees the real block (outside the fence) as current.
  run bash "$SCRIPT"
  [[ "$output" == ok:* ]]
}

@test "boundary: a CRLF template is read as LF — seeds fine, same id as the LF template" {
  bash "$SCRIPT" >/dev/null
  lf_id=$(id_of "$TARGET")
  rm "$TARGET"
  sed 's/$/\r/' "${PLUGIN_DIR}/templates/OUTPUT.md" > "$BATS_TEST_TMPDIR/crlf.md"
  run env OUTPUT_TEMPLATE="$BATS_TEST_TMPDIR/crlf.md" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == created:* ]]
  [ "$(id_of "$TARGET")" = "$lf_id" ]
  [ "$(grep -c $'\r' "$TARGET")" -eq 0 ]
}

@test "boundary: HOME unset -> hook exits 0 silently, script without a target exits 1" {
  run env -u HOME bash -c "printf '{}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run env -u HOME bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HOME is not set"* ]]
}

@test "boundary: hook is silent and writes nothing when OUTPUT.md does not exist" {
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TARGET" ]
}

@test "boundary: syncOutputTemplate=false in the global config -> hook does nothing" {
  printf 'mine\n' > "$TARGET"
  printf '{"syncOutputTemplate": false}\n' > "$GW_DIR/memory-loop.json"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'mine\n' | cmp -s - "$TARGET"
}

@test "boundary: repo config true overrides global false" {
  printf 'mine\n' > "$TARGET"
  printf '{"syncOutputTemplate": false}\n' > "$GW_DIR/memory-loop.json"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO/.groundwork"
  printf '{"syncOutputTemplate": true}\n' > "$REPO/.groundwork/memory-loop.json"
  run bash -c "printf '{\"cwd\":\"%s\"}' '$REPO' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [[ "$output" == "output style: merged:"* ]]
  grep -qxF -- "$CLOSE" "$TARGET"
}
