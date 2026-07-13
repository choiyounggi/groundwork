# groundwork v0.1 — Safe-by-default Claude Code harness starter pack

Goal: 로컬 RTB 안전 훅을 **탈-RTB 제네릭·설정가능** 버전으로 일반화한 `guardrails`
플러그인 + 이를 dev-loop와 함께 큐레이션하는 `groundwork` 마켓플레이스를 v0.1로 출시.
우선순위 = 커뮤니티 reach(GitHub 스타/공유). 엔터프라이즈 거버넌스는 이후 버전.

Acceptance:
- `/plugin marketplace add choiyounggi/groundwork` → `guardrails`·`dev-loop` 둘 다 노출
- `guardrails` 설치 시 위험 Bash(파괴/시크릿/공급망) 명령이 기본값으로 ask/block
- 규칙별 mode(off|ask|block) + 커스텀 패턴을 config로 조정 가능
- 모든 훅이 macOS+Linux에서 동작, bats 테스트 통과(언급 통과 / 실행 차단 양방향)
- RTB 내부 정보(URL·prd·EDR정책·회사명) 0건 유입

Stack: Bash(POSIX-호환) + jq, bats-core 테스트, GitHub Actions CI. MIT.

## Decisions

| # | Decision | Choice | 근거 |
|---|----------|--------|------|
| D1 | 가드 훅 형태 | 단일 PreToolUse Bash 훅, 최신 `hookSpecificOutput.permissionDecision`(deny/ask/allow) 스키마 | [no-wiki] CC 훅 스키마 (로컬 pre-bash-guard.sh emit_decision 패턴 승계) |
| D2 | 가드 규칙(탈-RTB) | **block**: curl\|sh 공급망, 디스크파괴(dd/mkfs/>/dev/sd*), fork-bomb / **ask**: rm -rf, git force-push·reset --hard·checkout ., DROP·TRUNCATE, kubectl delete, 민감파일(ssh/aws/.env/.npmrc), 클라우드 자원 삭제(aws/gcloud/az delete), 시크릿 export | infrastructure/ci-cd/secrets-handling.md + [no-wiki] 명령패턴 |
| D3 | **RTB 전용 규칙 제거** | `/tmp` SentinelOne EDR 차단·prd·objManager·회사 도메인 전부 제외. `/tmp` 차단은 **off 기본 옵션 규칙**으로만 남김 | 하드라인(회사 IP 미유입) |
| D4 | 정규식 앵커링 | 모든 패턴을 실행위치(`^`/`;`/`&`/`\|`/`&&`/`\|\|` 뒤)에만 앵커 + **양방향 bats 테스트**(언급은 통과, 실행은 차단) | platforms/shells/portable-shell-scripts.md + [no-wiki: guard-anchoring, self-habit] |
| D5 | 설정 우선순위 | `.groundwork/guardrails.json`(repo) > `~/.claude/groundwork/guardrails.json`(global) > 내장 기본. 규칙별 `mode` + `extraPatterns` | infrastructure/config/environment-config.md (dev-loop tools.json 선례) |
| D6 | 감사 훅 | PostToolUse, Bash+MCP 호출을 `~/.claude/groundwork/audit.jsonl`에 기록, chmod 600, 10MB 회전, **토큰류 값 redact**, BSD/GNU stat 폴백 | bsd-vs-gnu-cli.md + secrets-handling.md |
| D7 | 포터빌리티 | POSIX-호환 bash, grep -E, stat/date BSD·GNU 양쪽 폴백, jq 필요 시 advisory | platforms/tools/bsd-vs-gnu-cli.md + portable-shell-scripts.md |
| D8 | 마켓플레이스 | `plugins[]`에 guardrails(로컬 source) + dev-loop(`source:url` = choiyounggi/dev-loop.git). 로컬 source 정확 문법은 빌드 시 $schema로 확정 | [no-wiki] marketplace.schema.json 검증 |
| D9 | 테스트 | bats, 훅당 1파일, 각 파일 ≥ 차단1 + 통과1(양방향) + 설정오버라이드1 | [no-wiki] (D4 정신) |

## Task order

| Task | 내용 | Depends on | Parallel-ok |
|------|------|-----------|-------------|
| 01 | repo 뼈대: 루트 README(피치)·LICENSE(MIT)·.gitignore·marketplace.json(초안) | — | |
| 02 | guardrails 매니페스트: plugin.json + hooks/hooks.json | 01 | |
| 03 | config resolver + 기본 config + examples/guardrails.example.json | 02 | parallel-ok(04) |
| 04 | bash-guard.sh (D2 규칙, D4 앵커, D1 스키마, D5 config 소비) | 02 | |
| 05 | audit-log.sh (D6 일반화 + redact) | 02 | parallel-ok(04) |
| 06 | bats: bash-guard.bats + audit-log.bats (D9 양방향) | 04,05 | |
| 07 | guardrails README + marketplace.json에 dev-loop 참조 확정(D8) | 04,05 | |
| 08 | CI: .github/workflows/test.yml (bats 실행) — dev-loop test.yml 모델 | 06 | |

## Out of scope (v0.1)
- 엔터프라이즈: managed-settings 계층·policy-as-code·감사 집계·SSO — 이후 버전
- 유료 티어 훅 — reach 확보 후
- <60초 증명 벤치마크 — 별도 트랙(런칭 직전)
