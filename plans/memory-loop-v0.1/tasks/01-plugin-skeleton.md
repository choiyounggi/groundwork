# Task 01: Plugin skeleton — manifest, hooks registration, example config

## Objective
`plugins/memory-loop/` exists with a valid plugin manifest, a hooks.json wiring
three hook scripts (not yet written), and an example config. All three JSON
files parse with jq.

## Wiki pages (read these first, only these)
- (none — pure JSON, conventions come from Inputs)

## Inputs
- `plugins/guardrails/.claude-plugin/plugin.json` — copy the field shape (name, description, version, author, homepage, strict)
- `plugins/guardrails/hooks/hooks.json` — copy the registration shape (`${CLAUDE_PLUGIN_ROOT}` interpolation)
- `plugins/guardrails/examples/guardrails.example.json` — example-config convention
- Decisions that bind you: D5 (config precedence), D16 (version 0.1.0)

## Steps
1. Create `plugins/memory-loop/.claude-plugin/plugin.json`:
   - name `memory-loop`, version `0.1.0`, author/homepage identical to guardrails, `strict: false`
   - description: "A memory lifecycle for Claude Code's native file-based memory: a save gate against hallucinated memories, tiered expiry (short-tier memories archived — never deleted — when they lapse), a periodic learning-review nudge, a habit-distillation frame, and an optional identity setup (names for the user and the assistant). Local-only, English, no org-specific content."
2. Create `plugins/memory-loop/hooks/hooks.json`:
   - `SessionStart` (no matcher key): two command hooks in one group, in order — `bash ${CLAUDE_PLUGIN_ROOT}/hooks/identity-context.sh` then `bash ${CLAUDE_PLUGIN_ROOT}/hooks/memory-expiry-sweep.sh`
   - `Stop` (no matcher key): `bash ${CLAUDE_PLUGIN_ROOT}/hooks/learning-nudge.sh`
   - top-level `description` string, mirroring guardrails' style
3. Create `plugins/memory-loop/examples/memory-loop.example.json`:
   ```json
   {
     "nudgeInterval": 10,
     "extraMemoryDirs": ["~/my-notes/memory"]
   }
   ```
   with the same "copy to ~/.claude/groundwork/memory-loop.json (global) or <repo>/.groundwork/memory-loop.json (repo)" comment convention guardrails uses (JSON has no comments — guardrails uses a `_comment` key if present; check and mirror; otherwise add `"_comment"` first key).

## Deliverables
- `plugins/memory-loop/.claude-plugin/plugin.json`
- `plugins/memory-loop/hooks/hooks.json`
- `plugins/memory-loop/examples/memory-loop.example.json`

## Verify
- `jq . plugins/memory-loop/.claude-plugin/plugin.json plugins/memory-loop/hooks/hooks.json plugins/memory-loop/examples/memory-loop.example.json` → all parse, exit 0

## Out of scope
- The three hook scripts themselves (tasks 02–04), skills (05–06), README (07)
