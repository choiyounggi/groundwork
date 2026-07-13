# Finding: guardrails blocks even in `--dangerously-skip-permissions` (yolo) mode

**Date:** 2026-07-13 · **Verdict: BLOCKS ✓**

## Why this matters
Claude Code's built-in permission prompts are what `--dangerously-skip-permissions`
("yolo mode") turns **off**. Power users run yolo to avoid confirmation fatigue —
and lose their safety net. The question: does a PreToolUse hook still fire, and can
its `deny` still stop a command, when permissions are skipped?

## Experiment (falsifiable, 3-state)
- Sandbox with a wrapper hook registered as `PreToolUse(Bash)`. The wrapper
  `touch`es a `hook-called` marker, then execs the real `bash-guard.sh`.
- Guard config: a harmless marker command (`touch YOLO_MARKER`) set to **block**.
- Ran headless: `claude -p "run: touch YOLO_MARKER" --dangerously-skip-permissions`
  (haiku), from the sandbox.
- Read-out: no `hook-called` → hook didn't load; `hook-called` + `YOLO_MARKER`
  present → guard did NOT block; `hook-called` + no `YOLO_MARKER` → guard blocked.

## Result
- `hook-called`: **YES** — PreToolUse hooks run even in bypassPermissions.
- `YOLO_MARKER`: **absent** — the command never executed.
- Claude echoed back the guard's exact `permissionDecisionReason`.

**Conclusion:** a PreToolUse `deny` blocks the tool call even under
`--dangerously-skip-permissions`. guardrails protects yolo-mode sessions.

## Claim language (use verbatim; do not overstate)
✅ "Works even in `--dangerously-skip-permissions` (yolo) mode — a PreToolUse deny
still stops the command."
⚠️ Scope: verified for Bash PreToolUse deny on Claude Code (headless, 2026-07-13).
Not a claim about every tool type or future CC versions. Guardrails is defense in
depth, not a sandbox — it stops the patterns it knows.
