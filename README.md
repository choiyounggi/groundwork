# groundwork

**A safe-by-default, batteries-included Claude Code harness — starter pack.**

Give an AI coding agent a shell and it *will*, eventually, try to run `rm -rf`,
pipe a script from the internet straight into `sh`, force-push over history, or
`DROP` a table. `groundwork` puts the guardrails **and** the good habits in place
in one install — so the agent stays fast, and stays safe.

This marketplace bundles two plugins you can install together or à la carte:

| Plugin | What it gives you |
|--------|-------------------|
| **guardrails** | A safe-by-default Bash guard — **blocks** supply-chain (`curl \| sh`), disk-destroying (`dd`/`mkfs`), and fork-bomb commands; **asks** before `rm -rf`, force-push, `DROP`/`TRUNCATE`, `kubectl delete`, credential/`.env` access, cloud-resource deletion, and secret exports. Plus a **redacted** audit log. Every rule is configurable. |
| **[dev-loop](https://github.com/choiyounggi/dev-loop)** | A wiki-grounded implementation loop — plan against a semantic-layer best-practices wiki, verify every task (TDD / PDCA / Reflexion), and grow the wiki from what you actually learn. |

## Install

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
/plugin install dev-loop@groundwork
```

Install just the guard, just the loop, or both.

## Why not just a starter template?

Most Claude Code starters scaffold *structure*. `groundwork` ships **behavior**:

- **Safe by default** — the guard is active the moment you install it. Zero config required.
- **Configurable, not just opinionated** — every rule is `off` / `ask` / `block`, per-repo or global, plus your own patterns.
- **Proven** — the hooks are covered by [`bats`](https://github.com/bats-core/bats-core) tests (a *mention* of `rm -rf` passes; an *execution* is caught) and run in CI.

See [`plugins/guardrails/README.md`](plugins/guardrails/README.md) for the full rule list and configuration.

## Roadmap

v0.1 ships `guardrails` + `dev-loop`. Team governance — a managed-settings
hierarchy, policy-as-code, and audit aggregation — is next.

## License

MIT — see [LICENSE](LICENSE).
