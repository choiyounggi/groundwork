#!/usr/bin/env bats
# Tests for scripts/sync-dev-loop-pin.sh — moving the dev-loop tag pin.
#
# Exit codes under test: 0 already in sync, 3 pin updated, 2 usage/parse/shape
# error. A rewrite must touch ONLY the dev-loop ref + version.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-dev-loop-pin.sh"
  ROOT="${BATS_TEST_TMPDIR}/repo"
  MARKETPLACE="${ROOT}/.claude-plugin/marketplace.json"
  mkdir -p "${ROOT}/.claude-plugin"
}

_write_marketplace() {
  local ref="$1" version="$2"
  cat > "$MARKETPLACE" <<EOF
{
  "name": "groundwork",
  "plugins": [
    {
      "name": "guardrails",
      "source": "./plugins/guardrails",
      "version": "0.1.0"
    },
    {
      "name": "dev-loop",
      "source": {
        "source": "url",
        "url": "https://github.com/choiyounggi/dev-loop.git",
        "ref": "${ref}"
      },
      "version": "${version}"
    }
  ]
}
EOF
}

_pinned_ref() {
  jq -r '.plugins[] | select(.name == "dev-loop") | .source.ref' "$MARKETPLACE"
}

# --- happy path ----------------------------------------------------------------

@test "updates both ref and version when the pin is behind" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"v1.10.0 -> v1.11.0"* ]]
  [ "$(_pinned_ref)" = "v1.11.0" ]
  [ "$(jq -r '.plugins[] | select(.name == "dev-loop") | .version' "$MARKETPLACE")" = "1.11.0" ]
}

@test "already-pinned tag is a no-op with exit 0" {
  _write_marketplace "v1.11.0" "1.11.0"
  before="$(cat "$MARKETPLACE")"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"in sync"* ]]
  [ "$(cat "$MARKETPLACE")" = "$before" ]
}

@test "a version field that drifted from the ref is repaired" {
  _write_marketplace "v1.11.0" "1.10.0"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 3 ]
  [ "$(jq -r '.plugins[] | select(.name == "dev-loop") | .version' "$MARKETPLACE")" = "1.11.0" ]
}

@test "no other plugin entry is touched" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 3 ]
  [ "$(jq -r '.plugins[] | select(.name == "guardrails") | .source' "$MARKETPLACE")" = "./plugins/guardrails" ]
  [ "$(jq -r '.plugins[] | select(.name == "guardrails") | .version' "$MARKETPLACE")" = "0.1.0" ]
  [ "$(jq -r '.plugins[] | select(.name == "dev-loop") | .source.url' "$MARKETPLACE")" = "https://github.com/choiyounggi/dev-loop.git" ]
}

@test "downgrading to an older tag is allowed (rollback)" {
  _write_marketplace "v1.11.0" "1.11.0"
  run bash "$SCRIPT" v1.10.0 "$ROOT"
  [ "$status" -eq 3 ]
  [ "$(_pinned_ref)" = "v1.10.0" ]
}

# --- errors and boundaries ------------------------------------------------------

@test "usage error with no arguments" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "usage error with too many arguments" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" v1.11.0 "$ROOT" extra
  [ "$status" -eq 2 ]
}

@test "empty tag is rejected" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" "" "$ROOT"
  [ "$status" -eq 2 ]
}

@test "a branch name is rejected as a pin" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" main "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a vX.Y.Z release tag"* ]]
  [ "$(_pinned_ref)" = "v1.10.0" ]
}

@test "a bare version without the v prefix is rejected" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" 1.11.0 "$ROOT"
  [ "$status" -eq 2 ]
}

@test "a prerelease tag is rejected" {
  _write_marketplace "v1.10.0" "1.10.0"
  run bash "$SCRIPT" v1.11.0-rc.1 "$ROOT"
  [ "$status" -eq 2 ]
}

@test "missing marketplace file is an error, not a silent pass" {
  run bash "$SCRIPT" v1.11.0 "${BATS_TEST_TMPDIR}/nowhere"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not found"* ]]
}

@test "unparseable JSON is an error" {
  echo '{ this is not json' > "$MARKETPLACE"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unparseable"* ]]
}

@test "an empty plugins array yields no dev-loop entry to update" {
  echo '{"name":"groundwork","plugins":[]}' > "$MARKETPLACE"
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"found 0"* ]]
}

@test "an un-pinned dev-loop entry is reported, not blindly rewritten" {
  cat > "$MARKETPLACE" <<'EOF'
{
  "name": "groundwork",
  "plugins": [
    {
      "name": "dev-loop",
      "source": { "source": "url", "url": "https://github.com/choiyounggi/dev-loop.git" }
    }
  ]
}
EOF
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"found 0"* ]]
}

@test "duplicate dev-loop entries are refused rather than half-updated" {
  cat > "$MARKETPLACE" <<'EOF'
{
  "name": "groundwork",
  "plugins": [
    { "name": "dev-loop", "source": { "source": "url", "url": "u", "ref": "v1.9.0" }, "version": "1.9.0" },
    { "name": "dev-loop", "source": { "source": "url", "url": "u", "ref": "v1.10.0" }, "version": "1.10.0" }
  ]
}
EOF
  run bash "$SCRIPT" v1.11.0 "$ROOT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"found 2"* ]]
}

@test "the real marketplace file is in sync with its own pinned tag" {
  REAL_ROOT="${BATS_TEST_DIRNAME}/.."
  ref="$(jq -r '.plugins[] | select(.name == "dev-loop") | .source.ref' "${REAL_ROOT}/.claude-plugin/marketplace.json")"
  run bash "$SCRIPT" "$ref" "$REAL_ROOT"
  [ "$status" -eq 0 ]
}
