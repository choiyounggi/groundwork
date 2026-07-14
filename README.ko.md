# groundwork

[English](README.md) | **한국어**

**안전이 기본값인, 배터리 포함 Claude Code 하네스 — 스타터 팩.**

AI 코딩 에이전트에게 셸을 쥐여주면 *언젠가는* 반드시 `rm -rf`를 실행하거나,
인터넷의 스크립트를 그대로 `sh`에 파이프하거나, 히스토리 위로 force-push하거나,
테이블을 `DROP`하려 듭니다. `groundwork`는 가드레일**과** 좋은 습관을 설치
한 번으로 갖춰줍니다 — 에이전트는 빠르게, 그리고 안전하게 유지됩니다.
`--dangerously-skip-permissions`(yolo) 모드에서도 버팁니다: `deny`는 여전히
명령을 멈춥니다.

이 마켓플레이스는 세 개의 플러그인 — 안전, 품질, 지속성 — 을 묶어 제공하며,
함께 설치해도 되고 골라 설치해도 됩니다:

| 플러그인 | 제공하는 것 |
|--------|-------------------|
| **guardrails** | 안전이 기본값인 Bash 가드 — 공급망 공격(`curl \| sh`), 디스크 파괴(`dd`/`mkfs`), 포크밤 명령은 **차단(block)** 하고, `rm -rf`, force-push, `DROP`/`TRUNCATE`, `kubectl delete`, 자격증명/`.env` 접근, 클라우드 자원 삭제, 시크릿 export 앞에서는 **확인(ask)** 합니다. 여기에 시크릿이 **마스킹된** 감사 로그까지. 모든 규칙은 설정 가능합니다. |
| **[dev-loop](https://github.com/choiyounggi/dev-loop)** | 위키에 근거한 구현 루프 — 시맨틱 레이어 베스트프랙티스 위키에 대고 계획하고, 모든 태스크를 검증하며(TDD / PDCA / Reflexion), 실제로 배운 것으로 위키를 키워갑니다. |
| **memory-loop** | 에이전트를 위한 메모리 라이프사이클 — 환각 메모리를 막는 저장 게이트, 삭제 대신 보관하는 계층형 만료, 주기적 학습 리뷰 넛지, 습관 증류 프레임(HABITS.md), 그리고 선택적인 1회성 이름 설정(어시스턴트가 자기 이름을 직접 고를 수도 있습니다). |

## 설치

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
/plugin install dev-loop@groundwork
/plugin install memory-loop@groundwork
```

가드만, 루프만, 메모리만 — 또는 셋 다 설치하세요.

## 왜 그냥 스타터 템플릿이 아닌가?

대부분의 Claude Code 스타터는 *구조*를 스캐폴딩합니다. `groundwork`는
**행동**을 담아 배송합니다:

- **안전이 기본값** — 설치하는 순간 가드가 활성화됩니다. 설정 zero.
- **의견을 강요하지 않는 설정** — 모든 규칙이 `off` / `ask` / `block`, 레포별 또는 글로벌, 자신만의 패턴 추가 가능.
- **로컬 전용** — 명령 매칭은 당신의 머신에서 일어납니다. 클라우드 서비스로 아무것도 전송되지 않습니다.
- **증명됨** — 훅은 [`bats`](https://github.com/bats-core/bats-core) 테스트로 커버되고(`rm -rf`의 *언급*은 통과, *실행*은 잡힘) CI에서 돌아갑니다.

|                                            | CC 내장 권한 | 클라우드 가드레일 서비스 | **groundwork guardrails** |
|--------------------------------------------|:-----------------------:|:------------------------:|:-------------------------:|
| 셋업                                        | 세션마다 프롬프트       | API 키 + 클라우드 규칙   | 설치만, 설정 zero          |
| `--dangerously-skip-permissions`에서 동작    | 아니오¹                 | 제각각                   | **예** (검증됨)            |
| 패턴별 규칙 (`rm -rf` vs `DROP` vs `curl \| sh`) | 거칢                | 예                       | **예**                    |
| 레포에 커밋하는 팀 공유 설정                  | 제한적                  | 예 (클라우드)            | **예** (`.groundwork/`)   |
| 명령이 머신 밖으로 나감                      | 아니오                  | **예 — API로 전송**      | **아니오 — 완전 로컬**     |
| 시크릿 마스킹 감사 로그                      | 없음                    | 예 (클라우드)            | **예** (로컬)             |
| 테스트 / CI                                 | —                       | —                        | **예**                    |
| 비용                                        | 무료                    | 유료 티어                | 무료 · MIT                |

¹ 권한 프롬프트는 정확히 그 플래그가 꺼버리는 대상입니다. PreToolUse `deny`는 아닙니다 — FAQ 참고.

설치 직후 바로 확인해보세요 — `/guardrails:self-test`가 실제 위험 명령들을
가드에 통과시켜 각각의 block/ask 판정을 보여줍니다. **아무것도 실행하지 않고요.**

전체 규칙 목록과 설정은 [`plugins/guardrails/README.ko.md`](plugins/guardrails/README.ko.md)를 보세요.

## 당신의 것으로 만들기

groundwork는 갇힌 정원이 아니라, 확장해서 쓰는 작고 정직한 코어입니다:

- **guardrails** — 모든 규칙이 `off` / `ask` / `block`이고, `.groundwork/guardrails.json`에
  자신만의 `extraAsk` / `extraBlock` 패턴을 추가해 팀과 커밋으로 공유합니다.
- **dev-loop** — `/dev-loop:configure`로 capability role을 *당신의* 도구에 매핑하세요:
  `verify`는 테스트/빌드 명령에, `knowledge`는 자체 위키나 knowledge MCP에,
  `explore`는 코드 검색에, `design`은 Figma에. 번들된 베스트프랙티스 위키는
  `knowledge-flush` → 리뷰되는 PR을 통해 **배운 것으로부터 자랍니다**.
- **memory-loop** — 에이전트의 메모리와 습관은 직접 읽고 고칠 수 있는 평범한
  로컬 파일로 남습니다. 넛지 주기와 스윕 대상 디렉토리는
  `.groundwork/memory-loop.json`에서 조절하고, HABITS.md는 당신의 교정으로부터 키워가세요.

당신의 위키, 당신의 테스트, 당신의 패턴을 가져오세요 — 하네스가 맞춰 적응합니다.

## FAQ

**"Claude Code가 이미 권한을 물어보는데 — 왜 이게 필요하죠?"**
내장 권한은 거칠고 세션 단위입니다: `Bash`를 한 번 승인하면 더는 묻지 않습니다.
guardrails는 *특정 위험 패턴*을 매번 게이트하고, 팀 공유 설정과 시크릿 마스킹
감사 로그가 있으며 — 권한 프롬프트를 **꺼버린** 상태에서도 동작합니다.

**"`settings.json` 권한으로 그냥 되지 않나요?"**
일부 도구를 deny할 수는 있지만, "`curl | sh`와 `dd`는 차단하고, `rm -rf`와
`DROP` 앞에서는 *물어보고*, 나머지는 전부 허용하되 시크릿은 마스킹해서 전부
로깅하라"는 표현할 수 없습니다. 그게 바로 이 가드입니다.

**"`--dangerously-skip-permissions`(yolo) 모드에서도 동작하나요?"**
예 — 검증했습니다. 권한 프롬프트를 건너뛰어도 PreToolUse `deny`는 여전히
명령을 멈춥니다. 파워 유저에게 안전망이 필요한 순간이 정확히 그때입니다.
[검증 기록](docs/launch/yolo-finding.md)을 보세요.

## 로드맵

groundwork는 `guardrails` + `dev-loop` + `memory-loop`을 배송합니다. 다음은
팀 거버넌스 — managed-settings 계층, policy-as-code, 감사 로그 집계 — 입니다.

## 라이선스

MIT — [LICENSE](LICENSE) 참고.
