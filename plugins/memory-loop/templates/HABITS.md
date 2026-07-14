# HABITS — distilled working habits

Habits distilled from real corrections, incidents, and wins in past sessions.
Loaded into every session (via an import line in `~/.claude/CLAUDE.md`) so the
same lesson never has to be learned twice.

**Two axes — never mix them:**

- *Expression* defaults to **positive (🟢)**: not "don't do X" but "when X,
  the best move is Y".
- *Safety verdict* defaults to **conservative**: if the behavior, on failure,
  touches anything where damage remains (production data, external posts,
  secrets, long-term memory, destructive commands), it is a 🛑 hard line,
  written as a strong prohibition. **When ambiguous, treat it as 🛑.**

Positive framing never weakens the safety line. Warm form, strict verdict.

## Maintenance protocol

When you learn something (a mistake, a correction from the user, a praised
behavior), classify first:

1. Ask: *"If this behavior fails, does damage remain?"* — production data or
   infrastructure, outbound messages (chat, PRs, mail), secrets, long-term
   memory, safety hooks, release/operations decisions. Damage that is later
   repaired but already happened (costs, wrong external posts, polluted
   memory) counts as YES.
2. **YES →** add under `🛑 Hard lines` as a strong negative rule. If the
   pattern is mechanically detectable and keeps recurring, consider promoting
   it to a hook.
3. **NO →** add under `🟢 Practices` as a positive "when X, do Y" rule, and
   preserve the origin as `(← background: date — what happened)`.
4. **Merge, don't multiply.** Before adding, scan for an entry with an
   overlapping trigger and strengthen/merge it instead of appending a
   near-duplicate. Keep this list short and scannable.
5. **Escalation ladder.** Default home is this file. Promote to a **hook**
   when a hard line is clear, repeated, and mechanically enforceable; promote
   to a **skill** when a practice is really a reusable procedure. Leave a
   one-line `→ promoted to <hook/skill>` tombstone here. Promote sparingly —
   only when clear + repeated + valuable, all three.

## 🟢 Practices

<!-- Positive rules: "when X, do Y", each with its background note. Example:
- **Before asserting how an external API behaves, call it once and read the
  actual response.** (← background: 2026-01-15 — recommended a URL format
  that the service silently ignored; one real call would have caught it.)
-->

## 🛑 Hard lines

<!-- Strong prohibitions for damage-remaining territory. Example:
- **Never run a destructive command (DELETE / DROP / rm -rf) before a
  preflight: verify the actual target, measure the affected scope, and have a
  recovery path.** (← background: 2026-02-03 — truncated the wrong local
  database after trusting a container name over the configured host.)
-->
