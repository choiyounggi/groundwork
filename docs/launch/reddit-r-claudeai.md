# r/ClaudeAI launch post (draft)

> Respect the sub's self-promo norms: lead with the story and the "why", link once,
> ask for feedback. Post the repo link in a top comment if the sub prefers that.

## Title options
1. I gave Claude Code a shell, watched it try `curl | sh`, and built a guard that stops it — even in yolo mode
2. guardrails: a zero-config, local-only safety net for Claude Code (blocks `rm -rf`, `curl|sh`, `DROP`… works with `--dangerously-skip-permissions`)
3. Made Claude Code safe-by-default in one install — no cloud, no API key, MIT

## Body

I run Claude Code with `--dangerously-skip-permissions` a lot — the confirmation
prompts kill the flow. The problem: that flag is *exactly* the safety net, and now
it's off. One day an agent cheerfully reached for a `curl … | sh` installer and I
realized the only thing between it and my machine was luck.

So I built **guardrails** — a small PreToolUse hook that:

- **blocks** supply-chain (`curl | sh`), disk-destroying (`dd`, `mkfs`), and fork-bomb commands
- **asks** before `rm -rf`, force-push, `DROP`/`TRUNCATE`, `kubectl delete`, reading `~/.aws/credentials` / `.env`, and cloud-resource deletes
- keeps a **redacted** audit log (tokens/passwords masked before they're written)
- every rule is `off` / `ask` / `block`, per-repo or global, plus your own regexes

Two things I care about:

1. **It's fully local.** Commands are matched on your machine — nothing is sent to
   a cloud API. (Cloud guardrail services exist; they ship your commands off-box.)
2. **It works in `--dangerously-skip-permissions`.** I actually tested this headless:
   a PreToolUse `deny` still stops the command when permission prompts are skipped.
   That's when you need it most.

You can see it work in 10 seconds after install with `/guardrails:self-test` — it
runs the dangerous commands *through the guard as data* and shows each decision,
without executing any of them.

It ships in a small marketplace with a second plugin (`dev-loop`, a wiki-grounded
plan→verify loop) but the guard stands alone. Tests + CI included. MIT.

Install:
```
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
```

Repo: https://github.com/choiyounggi/groundwork

Honest asks: what dangerous patterns should it catch that it doesn't yet? And is
`ask` vs `block` tuned the way you'd want out of the box? Feedback welcome — this is
v0.x and I'll iterate.
