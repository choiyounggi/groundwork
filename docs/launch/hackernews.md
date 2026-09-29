# Hacker News submission (draft)

> HN convention: "Show HN:" prefix, title under 80 characters, no marketing
> words, link to the repo. The body below goes in the *text* field only if
> you submit as a text post; for a link post, paste it as the first comment.

## Title options

1. Show HN: Groundwork – a safe-by-default harness for Claude Code (local guard, Orca orchestration, zero-token judge)
2. Show HN: Groundwork – guardrails, a wiki-grounded dev loop, and a Jev-style decision gate for Claude Code
3. Show HN: I made my coding agent cheaper to read and harder to fool (Claude Code plugins, MIT)

Pick 1 unless it runs past 80 characters on your screen; then 2.

## URL

https://github.com/choiyounggi/groundwork

## Body / first comment

I run Claude Code unattended a lot, often with permission prompts off. Four
things kept going wrong, so I packaged the fixes as a plugin marketplace:

**1. The agent reaches for dangerous commands.** `guardrails` is a PreToolUse
hook that blocks `curl | sh`, `dd`, fork bombs, and asks before `rm -rf`,
force-push, `DROP`, `kubectl delete`, credential reads. Fully local, redacted
audit log, every rule `off`/`ask`/`block`. It holds in
`--dangerously-skip-permissions` mode, which I verified headless, because that
flag turns off exactly the prompt most people rely on.

**2. Work bigger than one session.** `dev-loop` plans against a best-practices
wiki, writes tests first, and its `orchestrate` command splits a goal into a
dependency graph of worker sessions. When the Orca CLI is installed it runs
Orca-native: every task phase is a tracked Task + Dispatch, the coordinator
blocks on pushed `worker_done` / `escalation` / `question` mail instead of
polling, and liveness asks two questions (is the terminal alive, is the pane
moving) so a wedged worker is caught rather than waited out. Without Orca it
falls back to plain tmux with the same guarantees. Headless workers that hit a
guardrails `ask` write a redacted escalation record and fail fast instead of
hanging on a prompt nobody can answer.

**3. Output that costs too much to read and to generate.** `memory-loop` ships
two always-loaded rule files that treat tokens as a budget. `OUTPUT.md` is an
explain-like-I'm-five style guide: conclusion first, one idea per sentence,
bullets and tables over prose, no narration, no pleasantries, applied to every
token the agent writes, including commit messages and PR bodies. The one thing
it never trims is evidence: test output, repro commands and raw errors stay in
full. `HABITS.md` holds distilled lessons and is capped at 8000 bytes / 24
rules by a hook, because an always-loaded file is re-read on every request.

**4. "Done" that isn't.** `jev-gate` uses a local decision model in the style
of TypeSafe's Jev: no text generation, just typed choices with calibrated
probabilities, ~0.75 s, zero tokens. A Stop hook shows it the agent's last
message and asks two questions: is this a done claim, and does it cite
evidence? Done at p ≥ 0.8 with evidence at p ≤ 0.2 gets bounced once with the
reason. The same model handles the grey zone of the Bash gate after a
hard-deny list and a read-only fast path, and it can never override the
deterministic rules. On my 50-case eval it missed 0 dangerous commands and
classified agent reports at 100%; the misses were all over-escalation.

Everything is local, MIT, bats-tested in CI. Install:

    /plugin marketplace add choiyounggi/groundwork
    /plugin install guardrails@groundwork   # or dev-loop, memory-loop, jev-gate

What I would like to hear: which dangerous patterns the guard should catch
that it does not, and whether a small local judge in the Stop hook is
something you would trust in your own loop.
