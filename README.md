# groundwork

**A safe-by-default, batteries-included Claude Code harness — starter pack.**

Give an AI coding agent a shell and it *will*, eventually, try to run `rm -rf`,
pipe a script from the internet straight into `sh`, force-push over history, or
`DROP` a table. `groundwork` puts the guardrails **and** the good habits in place
in one install — so the agent stays fast, and stays safe. It even holds in
`--dangerously-skip-permissions` (yolo) mode: a `deny` still stops the command.

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
- **Local-only** — commands are matched on your machine. Nothing is sent to a cloud service.
- **Proven** — the hooks are covered by [`bats`](https://github.com/bats-core/bats-core) tests (a *mention* of `rm -rf` passes; an *execution* is caught) and run in CI.

|                                            | CC built-in permissions | Cloud guardrail services | **groundwork guardrails** |
|--------------------------------------------|:-----------------------:|:------------------------:|:-------------------------:|
| Setup                                      | per-session prompts     | API key + cloud rules    | install, zero config      |
| Works in `--dangerously-skip-permissions`  | no¹                     | varies                   | **yes** (verified)        |
| Per-pattern rules (`rm -rf` vs `DROP` vs `curl \| sh`) | coarse       | yes                      | **yes**                   |
| Team-shared config in the repo             | limited                 | yes (cloud)              | **yes** (`.groundwork/`)  |
| Commands leave your machine                | no                      | **yes — sent to API**    | **no — fully local**      |
| Audit log with secret redaction            | no                      | yes (cloud)              | **yes** (local)           |
| Tests / CI                                 | —                       | —                        | **yes**                   |
| Cost                                       | free                    | paid tiers               | free · MIT                |

¹ Permission prompts are exactly what that flag turns off. A PreToolUse `deny` is not — see the FAQ.

Try it right after install — `/guardrails:self-test` feeds real dangerous commands
through the guard and shows each block/ask decision, **without executing any of them.**

See [`plugins/guardrails/README.md`](plugins/guardrails/README.md) for the full rule list and configuration.

## Make it yours

groundwork is a small, honest core you extend — not a walled garden:

- **guardrails** — every rule is `off` / `ask` / `block`, and you add your own
  `extraAsk` / `extraBlock` patterns in `.groundwork/guardrails.json`, committed and
  shared with your team.
- **dev-loop** — map its capability roles to *your* tools with `/dev-loop:configure`:
  point `verify` at your test/build command, `knowledge` at your own wiki or knowledge
  MCP, `explore` at your code search, `design` at Figma. The bundled best-practices wiki
  then **grows from what you learn** via `knowledge-flush` → reviewed PRs.

Bring your own wiki, your own tests, your own patterns — the harness adapts.

## FAQ

**"Claude Code already asks for permission — why do I need this?"**
Built-in permissions are coarse and per-session: approve `Bash` once and it stops
asking. guardrails gates *specific dangerous patterns* every time, with team-shared
config and a redacted audit log — and it still works when you've turned permission
prompts **off**.

**"Can't I just do this with `settings.json` permissions?"**
You can deny some tools, but not express "block `curl | sh` and `dd`, *ask* before
`rm -rf` and `DROP`, allow everything else, and log it all with secrets redacted."
That is what the guard is.

**"Does it work in `--dangerously-skip-permissions` (yolo) mode?"**
Yes — verified. A PreToolUse `deny` still stops the command even when permission
prompts are skipped. That is exactly when a power user needs a net. See
[the finding](docs/launch/yolo-finding.md).

## Roadmap

v0.1 ships `guardrails` + `dev-loop`. Team governance — a managed-settings
hierarchy, policy-as-code, and audit aggregation — is next.

## License

MIT — see [LICENSE](LICENSE).
