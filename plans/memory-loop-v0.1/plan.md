# memory-loop v0.1

Goal: Add a third plugin `memory-loop` to the groundwork marketplace — a memory
*lifecycle* layer on top of Claude Code's native file-based memory: capture
(periodic learning-review nudge), operation (a save gate + tier/expiry
frontmatter), retirement (expiry sweep to `archived/`, never deletion), a
habit-distillation frame (HABITS.md), and an identity feature (names for the
user and the assistant, offered once at session start, declinable).
Acceptance: all bats tests green, shellcheck clean, no Korean / no
personal or org-specific strings anywhere in the plugin, marketplace + README +
CI updated, everything in English.

Stack: bash 3.2-compatible hooks (jq dependency, same as guardrails), bats
tests, GitHub Actions CI. No other runtime.

## Decisions

| # | Decision | Choice | Wiki basis |
|---|----------|--------|------------|
| D1 | Hook interpreter & mode | `#!/usr/bin/env bash`, `set -uo pipefail` (no `-e`: hooks fail open), bash 3.2 compatible (no assoc arrays, no `${var,,}`), quote every expansion | platforms-shells-portable-shell-scripts |
| D2 | Expiry date comparison | Never use relative-date flags (`date -d` / `date -v` differ BSD/GNU). `TODAY=$(date +%Y-%m-%d)`; compare ISO strings lexically: `[[ "$exp" < "$TODAY" ]]` | platforms-tools-bsd-vs-gnu-cli |
| D3 | Expiry boundary | Exclusive: a file expires only when `expires < today`. On the expiry date itself it is still live. Stated in README; boundary bats case asserts it | testing-quality-minimum-case-set |
| D4 | Memory dir discovery | Hook stdin JSON `cwd` (fallback `$PWD`) → slug = `sed 's|[^a-zA-Z0-9]|-|g'` (verified against real `~/.claude/projects/` entries) → `$HOME/.claude/projects/<slug>/memory`. Plus every path in config `extraMemoryDirs` (leading `~` expanded). Missing dir → silent exit 0 | [no-wiki] (verified empirically on a live CC install) |
| D5 | Config precedence | Built-in default < `~/.claude/groundwork/memory-loop.json` (global) < `<cwd>/.groundwork/memory-loop.json` (repo). Same shape of lookup helper as guardrails' `effective_mode` | [no-wiki] (repo convention, mirrors guardrails) |
| D6 | State location | `~/.claude/groundwork/memory-loop/` holds `identity.json` and `nudge-counter`. No `/tmp`. Tests override `HOME` to a bats tmpdir instead of an env knob | platforms-shells-portable-shell-scripts (non-interactive env; no rc-dependent paths) |
| D7 | Nudge output | Stop hook prints `{"decision":"block","reason":...}` via `jq -cn` (renders as feedback, not an error). `stop_hook_active == true` → exit 0 (loop guard). jq replaces any python3 dependency | [no-wiki] (Claude Code Stop-hook contract) |
| D8 | Identity 3-way branch | `identity.json`: `{userName, assistantName, chosenBy: "user"\|"assistant", status: "set"\|"declined"}`. Absent file → print the one-time setup prompt. `status=="declined"` → silent. Both names present → inject names line. Malformed / partial → silent exit 0 (fail open) | [no-wiki] (product decision from the design discussion) |
| D9 | Context injection | SessionStart hooks print plain text to stdout (injected as session context). No CLAUDE.md edits ever; removal leaves no trace | [no-wiki] (Claude Code SessionStart contract) |
| D10 | Sweep scope | Only files with frontmatter `tier: short` AND `expires: YYYY-MM-DD` are swept. `expires_when` (conditional) and files without `tier` are never touched — pre-existing native memories are safe by default. `MEMORY.md` always skipped | [no-wiki] (compatibility contract with CC native memory) |
| D11 | Retirement = move | `mv` into `<memory-dir>/archived/` + stdout report asking the agent to tidy the MEMORY.md index and offer promotion of still-valid facts to `tier: long`. Never delete | [no-wiki] (design principle: reversible retirement) |
| D12 | Test discipline | Every bats test asserts a concrete value; bidirectional (fires / does not fire); error-path cases assert silence + exit 0; boundary case for D3. Malformed-JSON cases prove fail-open | testing-quality-minimum-case-set, testing-quality-tests-that-cannot-fail |
| D13 | Skills format | 4 skills (`setup`, `identity`, `remember`, `habit`), each `skills/<name>/SKILL.md` with `name`/`description` frontmatter, English, no org/personal content | [no-wiki] (CC plugin skill convention) |
| D14 | HABITS.md home | Default `~/.claude/groundwork/HABITS.md`; `setup` creates it from the template and *suggests* (never edits) an `@` import line for the user's `~/.claude/CLAUDE.md` | [no-wiki] (product decision) |
| D15 | Habit frame | Two axes kept from the design: expression default = positive (🟢 "when X, do Y"), safety verdict default = conservative (🛑 hard lines, negative form, ambiguous → 🛑). Judged by "does failure leave damage?" Escalation ladder: habit → hook/skill when clear+repeated+valuable | [no-wiki] (distilled methodology, genericized) |
| D16 | Versioning / attribution | plugin.json version 0.1.0; marketplace entry mirrors guardrails' shape; commits authored `choiyounggi <74581798+choiyounggi@users.noreply.github.com>`, no co-author trailers | [no-wiki] (repo convention) |

## Task order

| Task | Depends on | Parallel-ok |
|------|------------|-------------|
| 01-plugin-skeleton | — | — |
| 02-expiry-sweep-hook | 01 | — |
| 03-learning-nudge-hook | 01 | parallel-ok with 02 |
| 04-identity-hook | 01 | parallel-ok with 02, 03 |
| 05-identity-setup-skills | 01 | parallel-ok with 02–04 |
| 06-remember-habit-skills | 01 | parallel-ok with 02–05 |
| 07-plugin-readme | 02, 03, 04, 05, 06 | — |
| 08-repo-integration | 07 | — |
