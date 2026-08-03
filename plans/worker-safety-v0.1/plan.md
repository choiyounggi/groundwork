# worker-safety v0.1 — implementation plan

> Design of record: `plans/worker-safety-v0.1/design.md`. Decisions D1–D13 there
> govern every task; this file is the ordered, testable task breakdown.

**Goal:** Make guardrails escalate (not block) inside dev-loop worker sessions,
and harden the orchestrator's spawn/share/monitor scripts — no external
orchestrator dependency.

**Tech Stack:** bash 3.2-compatible hooks + jq + bats (guardrails); POSIX sh +
tmux + git + jq (dev-loop). English only; no `/tmp`; fail-open hooks.

## Global Constraints (verbatim from design)

- Standalone behavior unchanged: `GROUNDWORK_ESCALATION_DIR` unset ⇒ every rule
  behaves exactly as today. Every guardrails task must assert this.
- Redaction logic lives in exactly ONE file (`hooks/redact.sh`) after Task A1.
- Hooks: `#!/usr/bin/env bash`, `set -uo pipefail` (no `-e`), bash 3.2 (no assoc
  arrays, no `${var,,}`), quote every expansion, exit 0 on all paths.
- Commits: author `choiyounggi <74581798+choiyounggi@users.noreply.github.com>`,
  no co-author trailers (repo convention).
- Tests: each bats/case asserts a concrete value; bidirectional (fires / does
  not fire); at least one error and one boundary case per new behavior.

---

## Phase A — escalation contract end-to-end (P0)

### Task A1: extract `redact()` into a shared lib

**Files:** Create `plugins/guardrails/hooks/redact.sh`; Modify
`plugins/guardrails/hooks/audit-log.sh` (replace inline `redact()` with `source`);
Test: `plugins/guardrails/tests/audit-log.bats` (existing cases must stay green).

**Produces:** `redact <string>` → echoes the string with secrets masked. Same
regex set currently in `audit-log.sh:56-65`.

- [ ] Verify existing `audit-log.bats` is green (baseline).
- [ ] Create `redact.sh`: `#!/usr/bin/env bash` guard + `redact()` moved verbatim
      from `audit-log.sh`. Make it idempotent-safe to `source` (guard against
      double-definition not required; it's a plain function file).
- [ ] Modify `audit-log.sh`: `source "${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")}/redact.sh"`,
      delete the inline `redact()`.
- [ ] Run `audit-log.bats` — all green (behavior unchanged).
- [ ] Add one `redact.sh` unit case (via a tiny bats or reuse audit-log.bats):
      `gh_token=ghp_AAAAAAAAAAAAAAAAAA` ⇒ contains `REDACTED`, no raw token.
- [ ] shellcheck both files. Commit.

### Task A2: escalation sink in `bash-guard.sh`

**Files:** Modify `plugins/guardrails/hooks/bash-guard.sh`; Test:
`plugins/guardrails/tests/bash-guard.bats`.

**Consumes:** `redact()` from A1.
**Produces:** env contract `GROUNDWORK_ESCALATION_DIR`, `GROUNDWORK_TASK_ID`.

- [ ] **Test first** (bats), all asserting concrete output:
  - escalation ON: `GROUNDWORK_ESCALATION_DIR=$dir` + a command hitting an `ask`
    rule (e.g. `git push --force`) ⇒ decision `deny`, reason matches
    `escalated to coordinator`, AND exactly one `*.json` appears in `$dir` whose
    `.rule` == `git_force_push` and `.cmd` contains no raw secret.
  - escalation OFF (unset): same command ⇒ decision `ask` (unchanged), `$dir`
    absent/empty. (boundary: proves standalone untouched)
  - precedence: `GROUNDWORK_ESCALATION_DIR` set AND
    `GROUNDWORK_NONINTERACTIVE=1` ⇒ escalation wins (file written, deny), not a
    silent deny.
  - error path: `GROUNDWORK_ESCALATION_DIR` points at an unwritable path ⇒ still
    exits 0 and still denies (fail-safe: block rather than allow on record
    failure), no crash.
- [ ] Run tests — fail (no escalation logic yet).
- [ ] Implement: after `pd` (ask/deny) is resolved and before emitting JSON, if
      `pd == ask` and `-n "${GROUNDWORK_ESCALATION_DIR:-}"`:
      `mkdir -p "$dir"`; build record with `jq -cn` (ts via `date -u +%FT%TZ`,
      taskId `${GROUNDWORK_TASK_ID:-}`, rule, reason, `cmd=$(redact "$cmd")`,
      cwd `$PWD`); write to `"$dir/$(date +%s)-$RANDOM.json.tmp"` then `mv` to
      final `.json`; set `pd=deny`, reason=`"escalated to coordinator: <rule>"`.
      Source `redact.sh` near the top.
- [ ] Run tests — pass. shellcheck. Commit.

### Task A3: config upward traversal in `bash-guard.sh`

**Files:** Modify `plugins/guardrails/hooks/bash-guard.sh:25-26` (REPO_CFG);
Test: `bash-guard.bats`.

- [ ] **Test first:** write `.groundwork/guardrails.json` at a temp git repo root
      setting `rm_rf` → `block`; run the hook with `PWD` at a *subdirectory* of
      that repo on an `rm -rf` command ⇒ decision `deny` (proves the config was
      found from a subdir). Boundary: same but no config file ⇒ `rm_rf` default
      `ask`.
- [ ] Run — fail (literal PWD misses it).
- [ ] Implement: walk from `$PWD` upward looking for `.groundwork/guardrails.json`,
      stop at the git toplevel (`git rev-parse --show-toplevel 2>/dev/null`) or
      filesystem root. Set `REPO_CFG` to the first hit (empty if none). Keep
      `GLOBAL_CFG` and precedence unchanged.
- [ ] Run — pass. shellcheck. Commit.

### Task A4: worker config injection (dev-loop)

**Files:** Modify `dev-loop/skills/orchestrate/scripts/setup-worktrees.sh`;
Test: `dev-loop` bats/shell test for the script (create if the script has none).

- [ ] **Test first:** run setup for a task ⇒ `<wt>/.groundwork/guardrails.json`
      exists and (jq) has `rm_rf.mode=="off"`, `system_tmp_write.mode=="off"`,
      `git_discard.mode=="off"`, `cloud_delete.mode=="ask"`,
      `sql_drop.mode=="ask"`, `git_force_push.mode=="ask"`,
      `secret_export.mode=="ask"`, `curl_pipe_shell.mode=="ask"`,
      `worktree_escape.mode=="ask"`.
- [ ] Run — fail.
- [ ] Implement: after `git worktree add`, `mkdir -p "$path/.groundwork"` and
      write the JSON above via a heredoc (or `jq -n`). Idempotent (overwrite ok).
- [ ] Run — pass. shellcheck. Commit.

### Task A5: session naming + env export (dev-loop)

**Files:** Modify `dev-loop/skills/orchestrate/scripts/launch-session.sh`.

- [ ] **Test first:** two launches for the same task in one server ⇒ distinct
      tmux session names (assert names differ / include a run-id). Assert the
      launch command exports `GROUNDWORK_ESCALATION_DIR` and `GROUNDWORK_TASK_ID`
      (grep the constructed `send-keys` string).
- [ ] Run — fail.
- [ ] Implement: session name `lo-<n>-<runid>` (runid = short suffix passed in or
      derived per orchestration run, NOT time-based inside the script if the
      harness forbids it — accept it as an arg from the orchestrator). Prepend
      `export GROUNDWORK_ESCALATION_DIR=<abs .orchestration/escalations> &&
      export GROUNDWORK_TASK_ID=<task> &&` to the launched command.
- [ ] Run — pass. shellcheck. Commit.

### Task A6: watch supervision (dev-loop)

**Files:** Modify `dev-loop/skills/orchestrate/scripts/watch-status.sh` and
`dev-loop/hooks/loop-gate.sh`.

- [ ] **Test first:**
  - escalation surfaced: an escalation `*.json` present ⇒ watch prints an
    attention line naming the task and does not treat the run as complete.
  - liveness: a status file in a non-terminal phase but with no live tmux session
    ⇒ watch reports it as failed/dead (does not wait the full timeout). (Mock
    `tmux has-session` via a stub on PATH.)
  - waiting phase: a status file phase `waiting` ⇒ counted as attention, not done;
    `loop-gate.sh` treats `waiting` as non-terminal (blocks stop) but the reason
    string distinguishes it from an error.
- [ ] Run — fail.
- [ ] Implement: add an escalation-dir glob to the poll loop; add
      `tmux has-session -t "$session"` liveness per tracked session (map task→
      session via status file field or naming); add `waiting` to the phase
      vocabulary; update `loop-gate.sh`'s terminal set + reason.
- [ ] Run — pass. shellcheck. Commit.

**Gate A:** independent review (`Agent(code-reviewer)` or `/review`) of the full
Phase A diff before Phase B.

---

## Phase B — finding #1 remediation (P0)

### Task B1: guardrails version bump + docs

**Files:** Modify `plugins/guardrails/plugin.json` (version), the marketplace
manifest (`.claude-plugin/marketplace.json`), and `plugins/guardrails/README*`
(document the `GROUNDWORK_ESCALATION_DIR`/`GROUNDWORK_TASK_ID` env, the
`worktree_escape` rule, the curl refinement, and the worker/NONINTERACTIVE
footgun note the user asked for).

- [ ] Bump patch version (e.g. 0.1.0 → 0.1.1). Update marketplace entry to match.
- [ ] README: add an "Orchestration / worker sessions" section — env contract,
      per-worktree `.groundwork/guardrails.json` scoping, and the warning that
      `GROUNDWORK_NONINTERACTIVE=1` turns every `ask` into a hard `deny` (fine for
      CI, breaks worker sessions if misapplied — prefer the escalation env).
- [ ] Verify cache refresh path: document how the active plugin cache updates on
      version bump (reinstall / marketplace sync). Commit.

### Task B2: `remask-audit.sh` one-shot

**Files:** Create `plugins/guardrails/scripts/remask-audit.sh`; Test:
`plugins/guardrails/tests/remask-audit.bats`.

**Consumes:** `redact()` from A1.

- [ ] **Test first:**
  - a JSONL line whose `.summary` contains `GH_TOKEN=ghp_AAAA...` ⇒ after remask,
    `.summary` contains `REDACTED`, no raw token, and the rest of the record is
    byte-identical.
  - already-redacted line ⇒ unchanged (idempotent).
  - empty file / missing file ⇒ exit 0, no error (boundary).
  - dry-run default ⇒ input file unchanged, a preview printed.
- [ ] Run — fail.
- [ ] Implement: read `${GROUNDWORK_AUDIT_LOG:-~/.claude/groundwork/audit.jsonl}`
      (+ `*.old` rotations), for each line re-`redact` the `.summary` field via
      jq+redact, write to a sibling temp then `mv` only when `--apply` is passed;
      default is dry-run. Back up to `<log>.premask.bak` before applying. `chmod
      600` outputs. Never touch `/tmp`.
- [ ] Run — pass. shellcheck. Commit. (User runs `--apply` themselves.)

**Gate B:** review Phase B diff.

---

## Phase C — rule precision (P1)

### Task C1: curl_pipe_shell split

**Files:** Modify `plugins/guardrails/hooks/bash-guard.sh:77`; Test: `bash-guard.bats`.

- [ ] **Test first:**
  - `curl https://x/i.sh | sh` ⇒ `deny` (shell, unchanged).
  - `curl https://x/i.sh | bash` ⇒ `deny`.
  - `curl -s https://jira/rest | python3 -c 'import json,sys;...'` ⇒ `ask`
    (interp with `-c`, downgraded).
  - `curl https://x/i.py | python3` (bare, stdin=program) ⇒ `deny` (boundary).
  - `node -e '...'` piped ⇒ `ask`; `perl` bare piped ⇒ `deny`.
- [ ] Run — fail.
- [ ] Implement: keep the shell branch (`sh|bash|zsh|ksh|dash`) as `deny`. Add an
      interpreter branch (`python[0-9.]*|node|ruby|perl`): if the piped segment
      contains `-c`/`-e` ⇒ emit `ask`; else ⇒ `deny`. Register a rule id
      (`curl_pipe_interp` or reuse `curl_pipe_shell` reasons) so config can tune.
- [ ] Run — pass. shellcheck. Commit.

### Task C2: worktree_escape rule

**Files:** Modify `plugins/guardrails/hooks/bash-guard.sh` (registry + rule);
Test: `bash-guard.bats`.

- [ ] **Test first** (use a real temp git repo + linked worktree via `git worktree add`):
  - from the linked worktree, a command writing to the MAIN worktree abs path
    (`echo x > <main>/file`, `rm -rf <main>/dir`, `cp a <main>/b`) ⇒ `ask`
    (rule `worktree_escape`).
  - benign in-worktree write (`echo x > ./file`, abs path inside the worktree)
    ⇒ no fire (boundary — the critical false-positive guard).
  - not in a worktree at all ⇒ no fire, and NO extra `git` call when the command
    has no `/` (assert cheap-path via a `git` stub that records invocations).
- [ ] Run — fail.
- [ ] Implement: pre-check `case "$cmd" in */*) ... esac`; only then
      `git rev-parse --is-inside-work-tree` and derive the main worktree root
      from `git rev-parse --git-common-dir` (its parent when it ends in `/.git`;
      else `git worktree list --porcelain | head`). If cwd's toplevel differs
      from the main root AND the command contains the main root path AND a write
      verb (`>`,`>>`,`rm`,`mv`,`cp`,`tee`,`mkdir`,`touch`,`install`,`dd`) ⇒ emit
      the rule's mode (default `ask`). Add `worktree_escape` to the registry with
      a default and a reason string.
- [ ] Run — pass. shellcheck. Commit.

### Task C3: status-update atomicity

**Files:** Modify `dev-loop/skills/orchestrate/scripts/status-update.sh:25-27`.

- [ ] **Test first:** update phase + worktree + reworkCount in one call ⇒ the
      resulting file has all three fields and is valid JSON; simulate an
      interrupted write (kill between tmp-write and mv via a stub) ⇒ original
      file intact (never half-written).
- [ ] Run — fail.
- [ ] Implement: build the full object in ONE `jq` filter (all `--arg`s), write to
      one tmp, single `mv`.
- [ ] Run — pass. shellcheck. Commit.

**Gate C:** review Phase C diff. Then update `design.md` "Out of scope" if any
P2 item got pulled in.

---

## Self-review (plan vs design)

- Spec coverage: D1–D5,D8,D9,D11 → Phase A (A1–A6); D12 → B1; B2 remask; D6→C1;
  D7→C2; D10→C3. All decisions mapped. ✅
- No placeholders: every task names exact files, concrete test assertions, and
  the implementation approach. Trickiest (C2 detection) has the derivation
  spelled out. ✅
- Type/name consistency: `redact()` (A1) consumed by A2/B2; env names
  `GROUNDWORK_ESCALATION_DIR`/`GROUNDWORK_TASK_ID` identical across A2/A5/B1;
  `waiting` phase shared A6/loop-gate. ✅
