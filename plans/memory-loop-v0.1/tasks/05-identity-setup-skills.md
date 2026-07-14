# Task 05: identity + setup skills, HABITS.md template

## Objective
Two skills (`identity`, `setup`) and the HABITS.md template exist, in English,
each SKILL.md self-contained and consistent with the hook contracts from tasks
02–04 (file paths, JSON schema, config keys).

## Wiki pages (read these first, only these)
- (none — these are prose skill files; contracts come from Inputs)

## Inputs
- `plugins/guardrails/skills/self-test/SKILL.md` — frontmatter + tone convention
- Decisions that bind you: D6 (identity.json path), D8 (schema incl. `chosenBy`, `status` values), D14 (HABITS.md at `~/.claude/groundwork/HABITS.md`; suggest-only CLAUDE.md import), D15 (two-axis frame)

## Steps
1. `plugins/memory-loop/skills/identity/SKILL.md` — frontmatter `name: identity`,
   `description:` "Set, change, or decline the user/assistant names that memory-loop injects at session start. Use when the user wants to set up names, rename either party, or stop the name-setup offer."
   Body (English): the exact identity.json path and schema (D8); procedures:
   - **Set**: ask the user's preferred name; for the assistant's name offer both paths (user picks / assistant chooses and explains why — record `chosenBy` accordingly); write the file with `status: "set"` (create the directory with `mkdir -p` first); confirm by echoing the resulting names back.
   - **Change**: read current file, update only the changed fields.
   - **Decline**: write `{"status": "declined"}` — nothing else — and tell the user how to opt back in later (`memory-loop:identity`).
   - Never write the file without the user's explicit confirmation of the values.
2. `plugins/memory-loop/skills/setup/SKILL.md` — frontmatter `name: setup`,
   `description:` "First-time memory-loop setup: offer identity names, create HABITS.md from the template, write an initial config, and verify the hooks respond. Use right after installing the plugin."
   Body — an ordered checklist:
   1. Identity: run the `identity` skill flow (set or decline).
   2. HABITS.md: copy `${CLAUDE_PLUGIN_ROOT}/templates/HABITS.md` to `~/.claude/groundwork/HABITS.md` unless it already exists (never overwrite); then *suggest* the user add `@groundwork/HABITS.md`-style import to their own `~/.claude/CLAUDE.md` — show the exact line, do not edit their file.
   3. Config: offer to copy `examples/memory-loop.example.json` to `~/.claude/groundwork/memory-loop.json`, explaining `nudgeInterval` and `extraMemoryDirs`.
   4. Verify: run each hook once with a stub stdin (e.g. `printf '{}' | bash ${CLAUDE_PLUGIN_ROOT}/hooks/identity-context.sh`) and show the user what got injected.
3. `plugins/memory-loop/templates/HABITS.md` — the empty distillation frame (English), containing:
   - a short header: what this file is (habits distilled from real corrections and wins; loaded into every session via the user's CLAUDE.md import).
   - **Maintenance protocol**: when you learn something (a mistake or a praised behavior), first ask "if this behavior fails, does it leave damage (prod data, external posts, secrets, long-term memory, destructive ops)?" YES → add under 🛑 as a strong negative rule; NO → add under 🟢 as a positive "when X, do Y" rule with a `(← background: date, what happened)` note. Ambiguous → treat as 🛑. Before adding, check for an overlapping entry and merge instead of appending. Escalation ladder: when a habit is clear, repeated, and valuable, promote it to a hook or a skill and leave a one-line tombstone here.
   - `## 🟢 Practices` — empty section with one commented-out example entry.
   - `## 🛑 Hard lines` — empty section with one commented-out example entry.

## Deliverables
- `plugins/memory-loop/skills/identity/SKILL.md`
- `plugins/memory-loop/skills/setup/SKILL.md`
- `plugins/memory-loop/templates/HABITS.md`

## Verify
- Checklist: both SKILL.md files have valid frontmatter (`name`, `description`); every file path mentioned matches D6/D14 exactly; grep skills + templates for hardcoded user home paths and the private org/user terms list kept outside this repo → 0 hits; no Hangul: `grep -rn $'[\xea-\xed]' plugins/memory-loop/skills plugins/memory-loop/templates` → 0 hits

## Out of scope
- remember / habit skills (task 06); plugin README (07)
