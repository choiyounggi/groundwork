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

Right after installing, ask Claude to run **`/guardrails:self-test`**, or run it directly:

```bash
bash "$(dirname "$(command -v claude)")"/../plugins/guardrails/scripts/self-test.sh 2>/dev/null \
  || bash plugins/guardrails/scripts/self-test.sh   # from a checkout
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
| `sensitive_file` | ask | reads/moves of `~/.ssh/id_*`, `~/.aws/credentials`, `.netrc`, `.npmrc`, `.pgpass`, `.env` |
| `cloud_delete` | ask | `aws … delete/terminate/rb`, `gcloud … delete`, `az … delete` |
| `secret_export` | ask | `export SOMETHING_TOKEN/SECRET/API_KEY/PASSWORD=…` |
| `worktree_escape` | ask | a write (`rm`/`mv`/`cp`/`>`/…) into the **main** worktree from a linked worktree — a worker corrupting the shared checkout (best-effort) |
| `system_tmp_write` | **off** | writes under `/tmp`, `$TMPDIR`, `/private/var/folders` (opt in for EDR-restricted environments) |

`block` → the command is denied. `ask` → you get a confirmation prompt. Patterns
anchor command words at an execution position, so a *mention* of a dangerous
command inside a quoted argument does **not** trigger a block.

## Configure

Drop a `guardrails.json` at either level (repo overrides global overrides defaults):

- `<repo>/.groundwork/guardrails.json` — team-shared, committed with the repo
- `~/.claude/groundwork/guardrails.json` — your global default

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

See [`examples/guardrails.example.json`](examples/guardrails.example.json).

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

Scope which rules matter per worktree by dropping a `.groundwork/guardrails.json`
at the worktree root: loosen sandbox-harmless rules and keep the dangerous ones as
`ask` (which then escalate).

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
