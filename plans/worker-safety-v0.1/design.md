# worker-safety v0.1 — design

Date: 2026-08-04

Goal: Make guardrails safe and non-blocking inside dev-loop orchestration
*worker* sessions, and harden the dev-loop orchestrator's spawn/share/monitor
machinery — without depending on any external orchestrator (Orca). The binding
mechanism is a single environment-variable contract between the two repos:
dev-loop tells guardrails "you are a worker; escalate instead of blocking."

Two repos:
- `groundwork` — the `guardrails` plugin (session-local, becomes worker-aware
  only by *reacting* to an env var; keeps zero orchestration knowledge).
- `dev-loop` — the `orchestrate` skill scripts (owns all orchestration
  knowledge; sets the env, writes worker config, reads escalations).

Acceptance:
- guardrails: all `bash-guard.bats` green (incl. new escalation / curl / config
  / worktree_escape cases), shellcheck clean, no Korean / no personal or
  org-specific strings, English only. Redaction logic lives in exactly one file.
- dev-loop: status-update atomic; watch surfaces escalations + dead panes;
  worktrees get a scoped guardrails config; sessions get unique names.
- No behavior change for a *standalone* (non-worker) guardrails session: with
  `GROUNDWORK_ESCALATION_DIR` unset, every rule behaves exactly as today.

Stack: bash 3.2-compatible hooks (jq dependency, same as guardrails/memory-loop),
bats tests. dev-loop scripts are POSIX sh + tmux + git + jq (existing preflight).

## The escalation contract (load-bearing decision)

`GROUNDWORK_ESCALATION_DIR` (activation switch) + `GROUNDWORK_TASK_ID` (label),
both exported by dev-loop at worker spawn. When set, a rule that resolves to
`ask` is converted into an *observable event* instead of a blocking prompt:
guardrails writes an escalation record and returns `deny` with a reason that
tells the worker it was escalated to the coordinator. The coordinator (watch)
sees the record and can re-issue the step with approval. guardrails itself
learns nothing about orchestration — it only reacts to the env var.

## Decisions

| # | Decision | Choice | Basis |
|---|----------|--------|-------|
| D1 | Escalation activation | `GROUNDWORK_ESCALATION_DIR` set AND rule resolves to `ask` → write record + `deny`. Unset → unchanged behavior (standalone sessions untouched) | env-var contract chosen in brainstorming |
| D2 | Escalation vs NONINTERACTIVE precedence | Both turn `ask`→`deny`. Escalation takes precedence: if `GROUNDWORK_ESCALATION_DIR` is set, record the event (coordinator sees it) rather than silently deny. NONINTERACTIVE alone stays a silent deny (existing CI behavior) | worker sessions must be observable, not silently failing |
| D3 | Escalation record shape | `{"ts","taskId","rule","reason","cmd","cwd"}` JSONL-style single object per file. `cmd` is redacted. Filename `<epoch>-<rand>.json` (`$RANDOM`), atomic write (tmp inside the escalation dir → `mv`; never `/tmp`). `mkdir -p` the dir | mirrors audit record; no-/tmp security policy |
| D4 | Redaction single-source | Extract `redact()` into `hooks/redact.sh`, `source`d by both `audit-log.sh` and `bash-guard.sh`. Same regex, behavior unchanged. Kills the source↔cache drift that leaked tokens (finding #1) | DRY; drift was the actual incident |
| D5 | Config upward traversal | Replace literal `${PWD}/.groundwork/guardrails.json` with a walk from `$PWD` up to the git toplevel (stop at first hit or at git root / filesystem root). Global config path unchanged. Precedence unchanged: repo > global > built-in | `bash-guard.sh:26` uses literal PWD; a worker that `cd`s into a subdir currently misses its worktree config (verified) |
| D6 | curl_pipe_shell split | `sh\|bash\|zsh\|ksh\|dash` → keep `block` (stdin is always code). `python[0-9.]*\|node\|ruby\|perl`: with `-c`/`-e` present → downgrade to `ask` (stdin is data, local code is visible); without → keep `block` (stdin is the program) | data-pipe false positive; user's proposal |
| D7 | worktree_escape rule | New rule, default `ask`, in the registry (so it can be set `off`). Fires only when: command contains an absolute path (cheap pre-check) AND cwd is a *linked* worktree AND the command targets the main worktree's path with a write verb (`>`,`>>`,`rm`,`mv`,`cp`,`tee`,`mkdir`,`touch`,`install`,`dd`). git is shelled out only when the `/` pre-check passes | today's worst incident (workers wrote into the main worktree); false-positive risk acknowledged |
| D8 | Worker config content | dev-loop `setup-worktrees.sh` writes `<wt>/.groundwork/guardrails.json`: sandbox-harmless rules (`rm_rf`, `git_discard`, `system_tmp_write`) → `off`; genuinely dangerous rules (`cloud_delete`, `sql_drop`, `git_force_push`, `secret_export`, `curl_pipe_shell`, `worktree_escape`) → `ask` (which becomes escalate via env). Minimizes escalation noise | an isolated worktree is a sandbox; escalate only what still matters |
| D9 | Session naming | `launch-session.sh` appends a short run-id to `lo-N` so re-runs don't collide with / silently skip stale sessions | current `has-session` → silent skip clobbers prior state |
| D10 | status-update atomicity | Write all fields in ONE `jq` invocation, then a single `mv`. No per-field writes | current per-field jq → half-written file on crash |
| D11 | watch supervision | `watch-status.sh`: (a) glob `<escdir>/*.json` → surface new escalations as coordinator attention; (b) `tmux has-session` liveness → a dead pane fails fast instead of waiting the 1h timeout; (c) recognize a `waiting` phase (worker blocked on escalation). `loop-gate.sh` treats `waiting` as non-terminal-but-attention | orca's idle/busy/waiting mirrored with files |
| D12 | Versioning | Bump `guardrails` plugin version so the marketplace cache picks up the fixed redaction + new rules (this is how the stale cache in finding #1 gets refreshed). Marketplace entry updated to match | released-plugin cache refresh |
| D13 | Test discipline | Every bats test asserts a concrete value; bidirectional (fires / does not fire); escalation cases assert both the `deny` decision AND the written file; curl cases cover shell-block / interp-ask / interp-block; config case proves upward traversal; worktree_escape covers a true positive AND a benign in-worktree write (boundary) | testing-quality-minimum-case-set |

## Phasing (implement + independently review each before the next)

- **Phase A (P0) — escalation contract end-to-end**: D1–D5, D8, D9, D11.
  guardrails escalation sink + shared redact + config traversal; dev-loop worker
  config injection + session naming + watch supervision.
- **Phase B (P0) — finding #1 remediation**: D12 version bump (carries all
  guardrails changes into the cache) + a one-shot `audit.jsonl` re-masking script
  (dry-run default, backs up first, chmod 600, idempotent; the user runs it).
- **Phase C (P1) — rule precision**: D6 (curl split), D7 (worktree_escape),
  D10 (status atomicity — small, can ride along).

## Out of scope (deferred)

- Orca as a spawn/monitor substrate (direction 나) — optional P2, not this pass.
- conflict-matrix.json / interface-file contract for decomposition (axis 1 P2).
- `.orchestration/journal.jsonl` (axis 3 P2).
- broad_autofix, secret_grep rules (P2).

## Files touched

groundwork:
- `plugins/guardrails/hooks/redact.sh` (new)
- `plugins/guardrails/hooks/bash-guard.sh` (escalation, config traversal, curl, worktree_escape)
- `plugins/guardrails/hooks/audit-log.sh` (source redact.sh)
- `plugins/guardrails/tests/bash-guard.bats` (new cases)
- `plugins/guardrails/plugin.json` + marketplace + README (version bump, doc the env + rules)
- `scripts/remask-audit.sh` (new, Phase B)

dev-loop:
- `skills/orchestrate/scripts/setup-worktrees.sh` (worker config)
- `skills/orchestrate/scripts/launch-session.sh` (session name + env export)
- `skills/orchestrate/scripts/status-update.sh` (atomic)
- `skills/orchestrate/scripts/watch-status.sh` (escalation glob + liveness + waiting)
- `hooks/loop-gate.sh` (waiting = non-terminal)
