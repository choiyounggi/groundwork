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
| `curl_pipe_shell` | **block** | `curl`/`wget`/`fetch` piped into `sh`/`bash`/`python`/`node`/… (supply-chain) |
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
| `system_tmp_write` | **off** | writes under `/tmp`, `$TMPDIR`, `/private/var/folders` (opt in for EDR-restricted environments) |

`block` → the command is denied. `ask` → you get a confirmation prompt. Patterns
anchor command words at an execution position, so a *mention* of a dangerous
command inside a quoted argument does **not** trigger a block.

## Configure

Drop a `guardrails.json` at either level (repo overrides global overrides defaults):

- `<repo>/.groundwork/guardrails.json` — team-shared, committed with the repo
- `~/.claude/groundwork/guardrails.json` — your global default

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
for headless or CI agents where no human is there to confirm.

## Audit log

Every Bash and MCP tool call is appended (one JSON line) to
`~/.claude/groundwork/audit.jsonl` (override with `$GROUNDWORK_AUDIT_LOG`):

```json
{"ts":"2026-07-13T04:20:56Z","tool":"Bash","summary":"git push https://ghp_REDACTED@github.com/x/y","error":false,"cwd":"/repo"}
```

Common secret shapes (GitHub / AWS / Slack / OpenAI tokens, `Bearer …`,
`password=`/`token=`/`secret=`/`api_key=`) are redacted before writing. The file
is `chmod 600` and rotates at 10 MB. The hook never fails — a broken audit must
never block your work.

## Requirements

- `bash` (3.2+, macOS/Linux) and `jq` on `PATH`.

## Tests

```bash
bats plugins/guardrails/tests
```

Each hook has bidirectional coverage: dangerous commands are caught, mentions and
harmless commands pass, config overrides apply, and the audit log redacts secrets.
