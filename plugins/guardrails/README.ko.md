# guardrails

[English](README.md) | **한국어**

**안전이 기본값인 Claude Code 가드레일.** AI 에이전트가 셸로 저지를 수 있는
위험한 일들을 막는 `PreToolUse` Bash 가드와, 무엇이 실행됐는지 — 시크릿은
마스킹해서 — 기록하는 `PostToolUse` 감사 로그. 조직 특화 규칙 없이 어떤
프로젝트에서든 범용으로 동작합니다.

## 설치

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
```

설치 즉시 활성화, 설정 불필요.

## 셀프 테스트 (10초 만에 동작 확인)

설치 직후 Claude에게 **`/guardrails:self-test`** 를 요청하거나, 직접 실행하세요:

```bash
bash "$(dirname "$(command -v claude)")"/../plugins/guardrails/scripts/self-test.sh 2>/dev/null \
  || bash plugins/guardrails/scripts/self-test.sh   # 체크아웃에서 실행할 때
```

대표적인 위험 명령들(`curl | sh`, `rm -rf`, `DROP TABLE`, `kubectl delete`,
클라우드 삭제, …)을 **실제 가드**에 통과시켜 각각의 판정을 출력합니다 —
**아무것도 실행하지 않고요**:

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

`--dangerously-skip-permissions`(yolo) 모드에서도 동작합니다 — PreToolUse
`deny`는 여전히 명령을 멈춥니다. ([검증 기록](../../docs/launch/yolo-finding.md))

## 무엇을 막나

| 규칙 id | 기본값 | 트리거 |
|---------|---------|-------------|
| `curl_pipe_shell` | **block** | `curl`/`wget`/`fetch`를 `sh`/`bash`/`python`/`node`/… 로 파이프 (공급망 공격) |
| `disk_destroy` | **block** | `dd of=/dev/sd…`, `mkfs.… /dev/…`, `> /dev/sda` |
| `fork_bomb` | **block** | 고전적인 `:(){ :\|:& };:` |
| `rm_rf` | ask | recursive **와** force가 함께 붙은 `rm` (`-rf`, `-fr`, `--recursive --force`, …) |
| `git_force_push` | ask | `git push --force` / `-f` |
| `git_reset_hard` | ask | `git reset --hard` |
| `git_discard` | ask | `git checkout .` / `git restore .` |
| `sql_drop` | ask | `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE` |
| `kubectl_delete` | ask | `kubectl delete …` |
| `sensitive_file` | ask | `~/.ssh/id_*`, `~/.aws/credentials`, `.netrc`, `.npmrc`, `.pgpass`, `.env` 읽기/이동 |
| `cloud_delete` | ask | `aws … delete/terminate/rb`, `gcloud … delete`, `az … delete` |
| `secret_export` | ask | `export SOMETHING_TOKEN/SECRET/API_KEY/PASSWORD=…` |
| `system_tmp_write` | **off** | `/tmp`, `$TMPDIR`, `/private/var/folders` 밑 쓰기 (EDR 제한 환경에서 옵트인) |

`block` → 명령이 거부됩니다. `ask` → 확인 프롬프트가 뜹니다. 패턴은 명령어를
실행 위치에 앵커하므로, 인용된 인자 안에서 위험 명령을 *언급*하는 것만으로는
차단이 발동하지 **않습니다**.

## 설정

`guardrails.json`을 두 레벨 중 원하는 곳에 두세요 (레포 > 글로벌 > 기본값):

- `<repo>/.groundwork/guardrails.json` — 팀 공유, 레포에 커밋
- `~/.claude/groundwork/guardrails.json` — 내 글로벌 기본값

레포 설정은 현재 디렉토리에서 git 최상위까지 거슬러 올라가며 탐색되므로, 레포의
어느 하위 디렉토리에서도 적용됩니다. git 레포 밖에서는 현재 디렉토리만 확인합니다.

```jsonc
{
  "rules": {
    "rm_rf": { "mode": "ask" },          // off | ask | block
    "kubectl_delete": { "mode": "block" },
    "system_tmp_write": { "mode": "off" }
  },
  "extraAsk":   ["terraform[[:space:]]+(destroy|apply)"],  // 나만의 POSIX-ERE 패턴
  "extraBlock": ["(^|[[:space:];&|])shutdown[[:space:]]"]
}
```

[`examples/guardrails.example.json`](examples/guardrails.example.json)을 참고하세요.

### 비대화 / CI

`GROUNDWORK_NONINTERACTIVE=1`을 설정하면 모든 `ask`가 강한 `deny`로 바뀝니다 —
확인해줄 사람이 없는 headless/CI 에이전트에 유용합니다. 주의: *모든* `ask`를
거부하므로, 실제 작업을 해야 하는 오케스트레이션 워커에 걸면 정상 작업까지 조용히
실패합니다 — 그런 경우엔 아래 `GROUNDWORK_ESCALATION_DIR`를 쓰세요.

### 오케스트레이션 / 워커 세션

오케스트레이터가 띄운 headless 워커(예: tmux 세션) 안에서는 `ask` 프롬프트에
답할 사람이 없습니다. `GROUNDWORK_ESCALATION_DIR`(선택적으로
`GROUNDWORK_TASK_ID`)를 설정하면, `ask`가 될 규칙이 대신 해당 디렉토리에 **마스킹된**
에스컬레이션 레코드를 쓰고 `deny`를 반환합니다. 그러면 워커가 멈추는 대신 코디네이터가
그걸 보고 승인 후 단계를 재실행할 수 있습니다. 이는 `GROUNDWORK_NONINTERACTIVE`보다
우선합니다 — 둘 다 deny지만 에스컬레이션은 조용하지 않고 관측 가능합니다.

워크트리 루트에 `.groundwork/guardrails.json`을 두어 규칙 범위를 좁히세요:
샌드박스에서 무해한 규칙은 완화하고, 위험한 규칙은 `ask`로 유지(→ 에스컬레이션)합니다.

## 감사 로그

모든 Bash·MCP 도구 호출이 `~/.claude/groundwork/audit.jsonl`에 한 줄 JSON으로
누적됩니다 (`$GROUNDWORK_AUDIT_LOG`로 경로 변경 가능):

```json
{"ts":"2026-07-13T04:20:56Z","tool":"Bash","summary":"git push https://ghp_REDACTED@github.com/x/y","error":false,"cwd":"/repo"}
```

흔한 시크릿 형태(GitHub / AWS / Slack / OpenAI 토큰, `Bearer …`,
`password=`/`token=`/`secret=`/`credential=`/`api_key=`/`access_key=`,
`AWS_SECRET_ACCESS_KEY=…` 같은 대문자 환경변수, 공백으로 구분된 `configure set …`
시크릿 인자)는 기록 전에 마스킹됩니다. 마스킹은 정밀도를 우선합니다 — 키 이름
바로 뒤에 `=`/`:`가 와야 하므로, `token_type`·`secret_level` 같은 컬럼명은 로그에서
그대로 읽힙니다. 파일은 `chmod 600`이며 10 MB에서 로테이션됩니다. 이 훅은 절대
실패하지 않습니다 — 감사 로그가 깨져도 당신의 작업을 막아서는 안 되니까요.

## 요구사항

- `PATH`에 `bash`(3.2+, macOS/Linux)와 `jq`.

## 테스트

```bash
bats plugins/guardrails/tests
```

각 훅은 양방향으로 커버됩니다: 위험 명령은 잡히고, 언급·무해한 명령은
통과하며, 설정 오버라이드가 적용되고, 감사 로그는 시크릿을 마스킹합니다.
