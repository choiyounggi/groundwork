# HABITS — distilled working habits

Habits distilled from real corrections, incidents, and wins in past sessions.
Loaded into every session (via an import line in `~/.claude/CLAUDE.md`) so the
same lesson never has to be learned twice.

**Two files, one habit set.** This file holds the *rules* and is always loaded.
The prose explaining where each rule came from lives in `HABITS-CASES.md`,
which is **not** loaded automatically — rules here end with a `[Cnn]` pointer
into it. Read a case only when the rule alone does not settle the judgment.

That split matters because an always-loaded file is re-read on *every request*,
not once per session, so its size is multiplied by the length of the
conversation. Keep the rules here and let the stories live next door. 🛑 hard
lines are the exception: their background stays inline, because for a
prohibition the origin *is* the judgment you need.

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
3. **NO →** add under `🟢 Practices` as a positive "when X, do Y" rule. Put the
   origin in `HABITS-CASES.md` as a new `## Cnn` section and leave only the
   `[Cnn]` pointer on the rule here.
4. **Merge, don't multiply.** Before adding, scan for an entry with an
   overlapping trigger and strengthen/merge it instead of appending a
   near-duplicate. Keep this list short and scannable.
5. **Keep this file lean.** It is re-read on every request, so background prose
   accumulating here is a cost paid on every turn. When the learning-nudge hook
   reports that this file crossed the split threshold, move the remaining
   `(← background: …)` prose out to `HABITS-CASES.md` and leave pointers.
6. **Escalation ladder.** Default home is this file. Promote to a **hook**
   when a hard line is clear, repeated, and mechanically enforceable; promote
   to a **skill** when a practice is really a reusable procedure. Leave a
   one-line `→ promoted to <hook/skill>` tombstone here. Promote sparingly —
   only when clear + repeated + valuable, all three.

## 🟢 Practices

<!-- Positive rules: "when X, do Y". Keep the rule here and put its origin in
     HABITS-CASES.md under a matching `## Cnn`, leaving only the pointer:
- **Before asserting how an external API behaves, call it once and read the
  actual response.** [C1]
-->

## 🛑 Hard lines

<!-- Strong prohibitions for damage-remaining territory. Unlike practices, keep
     the background inline here — for a prohibition the origin is the judgment.
     Example:
- **Never run a destructive command (DELETE / DROP / rm -rf) before a
  preflight: verify the actual target, measure the affected scope, and have a
  recovery path.** (← background: 2026-02-03 — truncated the wrong local
  database after trusting a container name over the configured host.)
-->
