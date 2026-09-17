# HABITS — distilled working habits

Imported into every session, so it is re-read on **every request**: every byte
here is paid per turn. **Budget 8000 bytes / 24 rules**, enforced by
`habits-budget-guard.sh` — a write that grows this file past it is denied, a
write that shrinks it is always allowed. At budget, adding means merging,
archiving, or naming the rule this one replaces.

**Three gates before writing anything** — *damage* (does failure leave damage?
→ 🛑, else 🟢), *recurrence* (more than once?), *generality* (holds outside this
one tool or repo?). Fails a gate → the repo's own `CLAUDE.md`, the wiki, or
nowhere. Most go nowhere; that is the expected outcome. Routing table: the
`habit` skill.

**Positive form, conservative verdict** — "when X, do Y", not "don't do X"; but
if failure leaves damage it is a 🛑 prohibition. Ambiguous → 🛑.

Backgrounds: `HABITS-CASES.md`, pointed at by `[Cnn]`. Retired rules:
`HABITS-ARCHIVE.md`. Neither is loaded; neither is ever added to the import.

## 🟢 Practices

<!-- "when X, do Y", ~2 lines, origin in HABITS-CASES.md under a matching `## Cnn`:
- **Before asserting how an external API behaves, call it once and read the
  actual response.** [C1] -->

## 🛑 Hard lines

<!-- Prohibitions for damage-remaining territory. ONE sentence of inline origin;
     the full account goes to HABITS-CASES.md:
- **Never run a destructive command (DELETE / DROP / rm -rf) before a preflight:
  verify the target, measure the scope, have a recovery path.** (← 2026-02-03:
  truncated the wrong database, trusting a container name.) [C2] -->
