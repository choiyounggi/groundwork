#!/usr/bin/env bash
# groundwork / session-progress — build the dev-loop run fixture from dev-loop's
# own scripts, so the tests read what dev-loop really writes.
#
# The mod reads three files dev-loop owns: .orchestration/graph.json (graph-add.sh),
# .orchestration/status/<task>.json (status-update.sh) and .dev-loop/gates/<task>.md
# (templates/gates.md, flipped by gate-check.sh). Nothing else pins that format on
# this side, so a dev-loop release that renames a field would leave the worker view
# silently empty. CI regenerates this fixture against the pinned dev-loop and fails
# when the result differs from the committed tests/fixtures/dev-loop-run.ts.
#
# Usage: dev-loop-fixture.sh <dev-loop checkout> <scratch dir>   > tests/fixtures/dev-loop-run.ts
# The scratch dir is wiped and recreated. Needs jq. bash 3.2 compatible.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: dev-loop-fixture.sh <dev-loop checkout> <scratch dir>" >&2
  exit 2
fi
DL=$(cd "$1" && pwd -P)
S="$DL/skills/orchestrate/scripts"
GATE_CHECK="$DL/skills/loop-implement/scripts/gate-check.sh"
for f in "$S/graph-add.sh" "$S/status-update.sh" "$GATE_CHECK" "$DL/templates/gates.md"; do
  [ -f "$f" ] || { echo "dev-loop-fixture: missing $f — did dev-loop move it?" >&2; exit 2; }
done

rm -rf "$2"
mkdir -p "$2/run/.orchestration/status" "$2/run/.worktrees/task-1/.dev-loop/gates" "$2/run/.worktrees/task-2/.dev-loop/gates"
RUN=$(cd "$2/run" && pwd -P)
STATUS="$RUN/.orchestration/status"

# The graph: Phase 2 writes it once; graph-add.sh is dev-loop's only writer after that.
printf '{"tasks":[]}\n' > "$RUN/.orchestration/graph.json"
sh "$S/graph-add.sh" "$RUN/.orchestration/graph.json" '{"id":"task-1","deps":[],"files":[],"outputs":["api"]}' >/dev/null
sh "$S/graph-add.sh" "$RUN/.orchestration/graph.json" '{"id":"task-2","deps":["task-1"],"files":[],"outputs":["ui"]}' >/dev/null
sh "$S/graph-add.sh" "$RUN/.orchestration/graph.json" '{"id":"task-3","deps":[],"files":[],"outputs":["docs"]}' >/dev/null

# Statuses in the order a run writes them (orchestrate SKILL.md, templates/session-prompt.md). The seconds between
# steps keep "newer" strictly newer, as collect-status.sh requires.
unset TMUX
# 1. launch-session.sh pre-seeds each canonical record: pending, the worker's worktree and session.
for n in 1 2; do
  (cd "$RUN" && STATUS_DIR="$STATUS" STATUS_SESSION=worker-$n \
    sh "$S/status-update.sh" task-$n pending worktree="$RUN/.worktrees/task-$n" >/dev/null)
done
sleep 1
# 2. Workers write worktree-locally: task-1 planned and is now building under plan_ready; task-2 reported impl_done.
(cd "$RUN/.worktrees/task-1" && STATUS_DIR=.orchestration/status STATUS_SESSION=worker-1 \
  sh "$S/status-update.sh" task-1 plan_ready worktree="$PWD" >/dev/null)
(cd "$RUN/.worktrees/task-2" && STATUS_DIR=.orchestration/status STATUS_SESSION=worker-2 \
  sh "$S/status-update.sh" task-2 impl_done worktree="$PWD" >/dev/null)
# task-3 landed: the coordinator records done on the canonical copy.
(cd "$RUN" && STATUS_DIR="$STATUS" STATUS_SESSION=worker-3 sh "$S/status-update.sh" task-3 done >/dev/null)
sleep 1
# 3. The coordinator sends task-2 back twice on the canonical copy (no worktree= — it records its own path).
(cd "$RUN" && STATUS_DIR="$STATUS" sh "$S/status-update.sh" task-2 rework >/dev/null)
(cd "$RUN" && STATUS_DIR="$STATUS" sh "$S/status-update.sh" task-2 rework "error=tests failed" >/dev/null)

# Gate ledgers in the workers' worktrees, from the template: one runnable gate the checker flips, one manual gate
# left open. task-1's is named after loop-implement's own plan task, task-2's after the orchestrate task.
ledger() { # $1 worktree, $2 file name, $3 heading
  sed -e "s|^# Gates: .*|# Gates: $3|" \
    -e 's|^Scope: .*|Scope: the deliverable|' \
    -e 's|^- \[ \] G1: .*|- [ ] G1: the endpoint answers|' \
    -e 's|^  CHECK: .*|  CHECK: echo ALL PASS|' \
    -e 's|^  EXPECT: .*|  EXPECT: ALL PASS|' \
    -e 's|^- \[ \] G2: .*|- [ ] G2: the copy reads well|' \
    "$DL/templates/gates.md" > "$1/.dev-loop/gates/$2"
  # gate-check.sh is a bash script (Ubuntu's sh is dash, which misreads the gate ids). It exits 1 while a gate is
  # unmet, which G2 is on purpose, so the summary line is what says it ran as intended.
  local summary
  summary=$(cd "$1" && bash "$GATE_CHECK" --run ".dev-loop/gates/$2" 2>&1 | grep '^SUMMARY' || true)
  if [ "$summary" != "SUMMARY met=1 unmet=1 abandoned=0" ]; then
    echo "dev-loop-fixture: gate-check.sh did not flip exactly G1 in $2 (got: ${summary:-no summary})" >&2
    exit 3
  fi
}
ledger "$RUN/.worktrees/task-1" 01-api.md 01-api
ledger "$RUN/.worktrees/task-2" task-2.md task-2

FILES=".orchestration/graph.json .orchestration/status/task-1.json .orchestration/status/task-2.json
.orchestration/status/task-3.json .worktrees/task-1/.orchestration/status/task-1.json
.worktrees/task-1/.dev-loop/gates/01-api.md .worktrees/task-2/.orchestration/status/task-2.json
.worktrees/task-2/.dev-loop/gates/task-2.md"

# The order of events is what the reader depends on, so check that the clock gave it (each step strictly later than
# the one before, per record pair the reader compares) before normalising times away.
at() { jq -r .updatedAt "$RUN/$1"; }
if ! [ "$(at .orchestration/status/task-1.json)" \< "$(at .worktrees/task-1/.orchestration/status/task-1.json)" ] ||
   ! [ "$(at .worktrees/task-2/.orchestration/status/task-2.json)" \< "$(at .orchestration/status/task-2.json)" ]; then
  echo "dev-loop-fixture: status writes did not land in step order — rerun" >&2
  exit 3
fi

# What varies per run (the scratch path, clock times) is normalised; the shape and the step order are what is pinned.
# Each status record's time becomes its step: 00 pre-seed, 01 worker writes and task-3 done, 02 coordinator rework.
# The template's <!-- authoring rules --> block is dropped: the mod never reads it, and a wording change there would
# otherwise fail CI with no format change.
step_of() {
  case "$1" in
    .orchestration/status/task-1.json) echo 00 ;;
    .orchestration/status/task-2.json) echo 02 ;;
    *) echo 01 ;;
  esac
}
normalise() { # $1 relative path
  sed -e '/^<!--/,/^-->/d' -e "s|$RUN|/run|g" \
    -e "s|\"[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z\"|\"2026-01-01T00:00:$(step_of "$1")Z\"|g" \
    -e 's|[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}|2026-01-01 00:00:00|g' \
    "$RUN/$1"
}

echo '// GENERATED by scripts/dev-loop-fixture.sh from dev-loop'"'"'s own scripts — do not edit by hand.'
echo '// Keys are paths under the run root /run; values are the files as dev-loop wrote them.'
echo 'export const DEV_LOOP_RUN: Readonly<Record<string, string>> = {'
for rel in $FILES; do
  printf '  %s: %s,\n' "$(jq -Rn --arg p "/run/$rel" '$p')" "$(normalise "$rel" | jq -Rs .)"
done
echo '}'
