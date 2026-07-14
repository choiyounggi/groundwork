# Task 04: identity-context.sh + bats tests

## Objective
A SessionStart hook that injects the configured user/assistant names as
context, offers a one-time name setup when unconfigured, and stays silent
forever after a decline. Fail-open on malformed state.

## Wiki pages (read these first, only these)
- wiki/platforms/shells/portable-shell-scripts.md — quoting, fail-open structure
- wiki/testing/quality/minimum-case-set.md — the 3 branches are the behaviors; each needs its cases
- wiki/testing/quality/tests-that-cannot-fail.md — assert exact output substrings; assert silence explicitly

## Inputs
- `plugins/guardrails/hooks/bash-guard.sh` — header style, jq patterns
- `plugins/guardrails/tests/bash-guard.bats` — bats conventions
- Decisions that bind you: D6 (state file `~/.claude/groundwork/memory-loop/identity.json`), D8 (schema + 3-way branch + fail-open), D9 (plain stdout injection, no CLAUDE.md edits)

## Steps
1. Write `plugins/memory-loop/hooks/identity-context.sh`:
   - `IDENTITY="$HOME/.claude/groundwork/memory-loop/identity.json"`.
   - File absent → print the one-time setup prompt (English) and exit 0:
     ```
     [memory-loop] No identity is configured for this machine yet.
     In your first reply this session, briefly and naturally offer a one-time name setup (do not push if the user is mid-task):
       - Ask what the user would like to be called.
       - For your own name, offer both options: the user names you, or you choose a name yourself and say why you chose it.
       - Record the result with the memory-loop "identity" skill. If the user declines, record the decline so this offer never appears again.
     ```
   - File present: parse with jq. `STATUS=$(jq -r '.status // empty' ...)`; jq parse failure (`|| true`, empty vars) → exit 0 silently.
   - `status == "declined"` → exit 0, no output.
   - Else read `userName`, `assistantName`; if BOTH non-empty → print exactly:
     `The user's name is <userName>. Your name is <assistantName>. Address each other by name.`
     If `chosenBy == "assistant"`, append one sentence: `You chose this name yourself.`
   - Any other combination (partial fields, unknown status) → exit 0, no output.
2. Write `plugins/memory-loop/tests/identity-context.bats` (helper: fake `HOME`; write identity.json fixtures with `jq -cn`; run hook with stdin `{}`). Cases:
   - unset (no file) → output contains `[memory-loop] No identity` and `one-time name setup`.
   - set: `{userName:"Sam", assistantName:"Iris", chosenBy:"user", status:"set"}` → output is exactly the injection line (assert both names present, and absent `chose this name` sentence).
   - set with `chosenBy:"assistant"` → output additionally contains `You chose this name yourself.`
   - declined: `{status:"declined"}` → empty output, exit 0.
   - malformed JSON file (`{oops`) → empty output, exit 0 (fail-open — NOT the setup prompt: a broken file must not re-trigger the offer).
   - partial: `{userName:"Sam", status:"set"}` (no assistantName) → empty output, exit 0.

## Deliverables
- `plugins/memory-loop/hooks/identity-context.sh`
- `plugins/memory-loop/tests/identity-context.bats`

## Verify
- `bats plugins/memory-loop/tests/identity-context.bats` → all pass
- `shellcheck -s bash plugins/memory-loop/hooks/identity-context.sh` → clean

## Out of scope
- The identity skill that writes identity.json (task 05)
