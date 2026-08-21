# HABITS — case records (background prose)

Why each rule in `HABITS.md` exists: the actual mistake, correction, or praised
behavior it was distilled from.

**HABITS.md loads on every request. This file does not.** That split is the
whole point: a rule changes behavior, while its origin story is only needed
when the rule alone leaves you unsure. So the rule stays in the always-loaded
file and the prose lives here, fetched on demand.

Rules point here with a `[Cnn]` marker. Add a matching `## Cnn` section below,
newest last, and never renumber — a pointer that goes stale is worse than a
long file.

🛑 hard lines are the exception: their background stays inline in `HABITS.md`,
because for a prohibition the origin *is* the judgment you need at the moment
you are about to cross it.

---

<!-- Example of the layout — replace with real records.

## C1 — Before asserting how an external API behaves, call it once

(← background: 2026-01-15 — recommended a permalink URL format from memory;
the service silently ignored that parameter and the feature did nothing. One
real call to the endpoint would have shown the response shape immediately.)

## C2 — Verify the actual target before a destructive command

(← background: 2026-02-03 — truncated 84 rows in a local container database
after trusting a container name, while the configured host in `.env` pointed
somewhere else entirely. The real target still had its data; the wrong one
lost it.)

-->
