# memory-loop

[English](README.md) | **한국어**

**Claude Code 네이티브 파일 기반 메모리를 위한 메모리 라이프사이클.**

Claude Code는 이미 메모리를 *저장*할 수 있습니다. 없는 것은 라이프사이클입니다:
사실이 검증 없이 저장되고(나중에 진실인 것처럼 회상되고), 일회성 메모가 영원히
쌓이고, 한 세션에서 배운 교훈이 다음 세션 전에 증발합니다. 이 플러그인은 저장소
둘레에 그 루프를 더합니다:

```
수집 ──────────────► 운영 ──────────────► 소멸
교정 시그널          저장 게이트 +          만료 스윕 →
(교정 감지 시)        tier/expires,         archived/ (삭제는 절대 없음)
                     consolidate
```

그리고 라이프사이클이 있어야 가능해지는 두 가지:

- **HABITS.md** — 교정과 사고를 상시 행동으로 바꾸는 증류 프레임 (긍정 프랙티스 🟢,
  하드 라인 🛑). 기록 전 세 개의 게이트(damage → 🛑/🟢, recurrence, generality)를
  통과해야 하고, 파일 자체에 **예산**이 걸려 있습니다 — 8000바이트 / 규칙 24개를
  PreToolUse 가드가 쓰기 시점에 강제합니다. 항상 로드되는 파일은 매 요청마다 다시
  읽히기 때문입니다. 사례 기록은 `HABITS-CASES.md`, 은퇴한 규칙은
  `HABITS-ARCHIVE.md`에 두고 둘 다 로드하지 않으며 `[Cnn]` 포인터로 필요할 때만
  읽습니다.
- **Identity** — 사용자와 어시스턴트 *양쪽의* 이름을 정하는 1회성·거절 가능한
  제안 (어시스턴트가 자기 이름을 직접 고를 수도 있습니다). 매 세션 컨텍스트로
  주입됩니다. 이름으로 부를 수 있는 연속성.

## 설치

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install memory-loop@groundwork
```

그다음 `/memory-loop:setup`을 실행하세요 (슬래시 커맨드 전용) — identity,
습관 파일, 설정을 안내하고 훅이 응답하는지 검증합니다.

## 단일 파일 HABITS.md에서 업그레이드

훅과 스킬은 플러그인과 함께 갱신되지만 **여러분의 HABITS.md는 갱신되지 않습니다.**
템플릿은 `setup`이 복사할 때만 쓰이고, `setup`은 이미 있는 파일을 덮어쓰지 않기
때문입니다. 그래서 업그레이드 후에는 코드만 2계층 구조를 알고 데이터는 그대로인
상태가 됩니다. 그 간격을 메우려면:

1. `/memory-loop:setup`을 다시 실행하세요 — `HABITS-CASES.md`가 생성되고 HABITS.md는
   그대로 유지됩니다.
2. `habit` 스킬의 마이그레이션 절차를 요청하세요 — 각 🟢/⚙️ 항목의
   `(← background: …)` 산문을 사례 파일의 `## Cnn` 섹션으로 옮기고 규칙에는
   `[Cnn]`만 남깁니다. 🛑 항목은 그대로 둡니다.
3. CLAUDE.md의 import는 HABITS.md만 가리키게 유지합니다.

그냥 두어도 됩니다 — 단일 파일 HABITS.md는 계속 동작합니다. 파일이
`habitsSplitWarnBytes`를 넘으면 SessionStart 메모리 업킵 체크가 분리를 안내하며,
사례 파일이 아직 없으면 그 사실도 함께 알려줍니다.

## 1.x에서 업그레이드

Stop 훅 학습 넛지는 제거되었습니다. 설정의 `nudgeInterval`은 이제
무시됩니다(경고 없음 — 그 키를 그냥 읽지 않습니다). 두 역할은
분리되었습니다: `correction-signal.sh` 훅(UserPromptSubmit)이 교정을
실시간으로 감지해 `correctionInjectionCap`(기본 3)으로 상한을 두고,
습관 파일의 바이트 예산/규칙 수 상한/분리 임계값 체크는
`memory-staleness-check.sh`의 SessionStart 보고로 옮겨져 매 세션
평가됩니다. 업그레이드 후 둘 다 기본으로 동작하므로 따로 마이그레이션할
것은 없습니다.

## 네이티브 메모리와의 관계

memory-loop은 네이티브 메모리 포맷을 **확장**합니다. 재정의하지 않습니다.

- frontmatter `metadata` 밑에 라이프사이클 키를 추가합니다: `tier: long|short`,
  short에는 `expires: YYYY-MM-DD` 또는 `expires_when: "<이벤트>"`.
- `tier` 키가 **없는** 파일은 라이프사이클 밖입니다 — 스윕이 절대 건드리지
  않습니다. 플러그인 설치 전에 존재하던 모든 메모리는 기본적으로 면역입니다.
- 제거해도 모든 메모리는 그 자리에 그대로 남습니다.

## dev-loop과의 관계

dev-loop의 지식 루프는 *프로젝트·엔지니어링* 지식을 리뷰되는 팀 위키로
수집합니다. memory-loop은 *에이전트 자신의* 작업 기억과 습관을, 머신별로,
로컬에 수집합니다. 둘은 합쳐집니다: 하나는 공유 베스트프랙티스를 키우고,
다른 하나는 연속적이고 자기교정하는 에이전트를 키웁니다.

## 훅

| 훅 | 이벤트 | 하는 일 |
|------|-------|--------------|
| `identity-context.sh` | SessionStart | "The user's name is X. Your name is Y." 주입 — 미설정이면 1회성 이름 설정 제안, 거절 후엔 영원히 침묵 |
| `memory-staleness-check.sh` | SessionStart | 어떤 정리 버킷이 발화했는지(재검증, 인덱스 드리프트, 깨진 링크, 고아 파일, 비대한 인덱스, 밀린 consolidate, 그리고 항상 평가되는 습관 예산/규칙수/분리 임계값 체크) 한 줄로 요약하고 `~/.claude/groundwork/memory-loop/staleness-last-detail.md`를 가리킴 — 보고할 것이 없으면 침묵. 보고만 하고 쓰지 않음 |
| `memory-expiry-sweep.sh` | SessionStart | 만료된 `tier: short` 메모리를 `archived/`로 이동(삭제 아님)하고, 개수를 담은 한 줄과 `~/.claude/groundwork/memory-loop/expiry-sweep-last.md` 경로를 출력 — 에이전트가 인덱스를 정리하고 승격을 제안하게 함; 만료된 것이 없으면 침묵 |
| `habits-budget-guard.sh` | PreToolUse (Edit\|Write) | 습관 파일을 예산(바이트/규칙 수) 너머로 키우는 쓰기를 거부 — 파일을 줄이는 쓰기는 항상 허용하므로 빠져나갈 길은 막지 않음 |
| `correction-signal.sh` | UserPromptSubmit | 프롬프트가 교정처럼 보이면(한국어/영어 키워드) `signals.jsonl`에 한 줄을 기록하고, 습관이나 메모리 캡처를 제안하는 컨텍스트 한 줄을 주입 — 세션당 `correctionInjectionCap`(기본 3)으로 상한, 상한을 넘어도 기록은 계속됨 |
| `tutor-due-check.sh` | SessionStart | 복습 대기 항목이 있을 때 개수와 `/memory-loop:tutor` 스킬을 담은 한 줄, 아니면 침묵 — 한 줄이라 별도 상세 파일은 없음 |

## 스킬

| 스킬 | 용도 |
|-------|---------|
| `setup` *(슬래시 커맨드 전용)* | 최초 세팅 안내: identity → HABITS.md + HABITS-CASES.md → 설정 → 검증 |
| `identity` | 사용자/어시스턴트 이름 설정·변경·거절 |
| `remember` | 저장 게이트: 근거 확인 → tier 확인 → 만료 확인 → 기록 |
| `consolidate` | long-tier 메모리 **와 습관 파일**을 주기적으로 통합 — 중복 병합·모순은 최신 진실로 해소·날짜 절대화·HABITS.md를 예산 이내로 복귀 — 쓰기 전 확인을 거치고, `archived/`(메모리) 또는 `HABITS-ARCHIVE.md`(규칙)로 보내며 삭제는 하지 않음 |
| `habit` | damage/recurrence/generality 게이트를 통과한 교훈만 HABITS.md로 증류 (🟢 프랙티스 / 🛑 하드 라인) — 배경은 `HABITS-CASES.md`에 두고 `[Cnn]` 포인터만 남김, 증식 대신 병합, 게이트에 걸린 후보는 레포 CLAUDE.md나 위키로 라우팅, 필요 시 훅/스킬로 승격 |
| `tutor` | HABITS.md에 이미 쌓인 교훈을 대상으로 한 간격 반복 자가 퀴즈 — 복습 항목마다 새로운 전이 질문 하나, anti-sycophancy 채점, 1-4 회상 평점 |

## 튜터 (tutor)

`habit`이 교정과 사고를 상시 실천으로 바꾼다면, `tutor`는 그 실천이 실제로
내재화됐는지 검증해 루프를 닫습니다.

- **동기화** — 이미 추적 중인 항목(`list`)을 HABITS.md의 🟢/🛑 항목과
  대조합니다. 아직 커버되지 않은 항목이 있으면 새 항목을 제안하되, 반드시
  사용자 확인을 거친 뒤에만 생성합니다(원본 메모리에서 대량 생성하지 않음).
- **퀴즈** — 복습 대상 항목마다(`tutorSessionCap`으로 상한) 새로운 전이
  질문 하나를 묻습니다(교훈의 원본 사건을 그대로 재질문하지 않음). 비공개
  모범 답안과 대조해 판정 전에 오개념을 먼저 진단하고(anti-sycophancy),
  "왜/이게 바뀌면?" 후속 질문을 하나 던진 뒤, 사용자가 1-4 회상 평점을
  확인해야만 기록합니다.
- **리마인드** — `tutor-due-check.sh`(SessionStart)는 복습 항목이 대기
  중일 때 조용한 한 줄을 출력하고, 아니면 침묵합니다.

스케줄링은 Leitner 박스 기반입니다(5개 박스, 간격 1/3/7/21/60일; 평점 1은
박스 0으로 리셋, 2는 박스 유지, 3-4는 박스를 올립니다 — 그리고 항목이 박스
3 이상에 도달한 뒤로 평점 3 이상을 3회 연속 받으면 은퇴합니다). 모든 복습은
타임스탬프가 찍힌 로그
(`item_id`, `rating`, `ts`)로 남아 — 이는 향후 FSRS 방식 스케줄러가 상태
마이그레이션 없이도 소비할 수 있는 구조입니다.

상태는 `~/.claude/groundwork/memory-loop/tutor/{items.json,reviews.jsonl}`에
있으며, 전적으로 `tutor-schedule.sh`가 소유합니다 — 직접 수정하지 마세요.

| 키 | 기본값 | 의미 |
|-----|---------|---------|
| `tutorSessionCap` | `3` | `due` 호출마다 노출되는 최대 복습 항목 수(세션 퀴즈 크기) |
| `tutorEnabled` | `true` | `false`로 설정하면 리마인드 훅과 `due` 서브커맨드가 조용해짐 |

## 설정

선택사항입니다. `examples/memory-loop.example.json`을
`~/.claude/groundwork/memory-loop.json`(글로벌) 또는
`<repo>/.groundwork/memory-loop.json`(레포, 팀 공유)으로 복사하세요.
레포 > 글로벌 > 내장 기본값 순으로 우선합니다.

| 키 | 기본값 | 의미 |
|-----|---------|---------|
| `correctionInjectionCap` | `3` | 세션당 교정 시그널 컨텍스트 주입 최대 횟수; `0`이면 주입은 비활성화되지만 `signals.jsonl` 기록은 계속됨 |
| `habitsBudgetBytes` | `8000` | 항상 로드되는 습관 파일의 크기 예산. 이를 넘기는 쓰기는 거부되고, 메모리 업킵 체크(`memory-staleness-check.sh`)가 매 세션 이를 보고함 (`0`이면 비활성) |
| `habitsMaxRules` | `24` | 습관 파일의 규칙 수 상한 — 🟢과 🛑을 합쳐서 셈 (`0`이면 비활성) |
| `habitsSplitWarnBytes` | `40000` | 습관 파일이 이 크기를 넘으면 메모리 업킵 체크가 배경 산문을 사례 파일로 옮기도록 함께 보고 (`0`이면 비활성) |
| `habitsPath` | `~/.claude/groundwork/HABITS.md` | 예산 가드와 크기 검사가 읽을 습관 파일 — 다른 경로의 파일을 import해서 쓰면 이 값을 지정 (`~` 지원) |
| `habitsCasesPath` | `habitsPath` 옆의 `HABITS-CASES.md` | 그 사례 기록 파일의 경로 (`~` 지원) |
| `memoryReviewDays` | `90` | 이 기간 동안 손대지 않은 메모리는 재검증 후보가 됨 (`0`이면 비활성) |
| `memoryIndexMaxLines` | `120` | 정리 패스를 권할 `MEMORY.md` 줄 수 (`0`이면 비활성) |
| `consolidateIntervalDays` | `30` | 마지막 consolidate 실행이 이보다 오래됐으면 보고 (`0`이면 비활성) |
| `memoryCheckCooldownDays` | `7` | 업킵 보고 후 이 기간 동안 침묵 (`0`이면 매 세션 보고) |
| `extraMemoryDirs` | `[]` | 현재 프로젝트의 메모리 디렉토리 외에 추가로 스윕할 디렉토리 (`~` 지원) |

상태(identity, `signals.jsonl`, `correction-sessions/`,
`expiry-sweep-last.md`, `staleness-last-detail.md`)는
`~/.claude/groundwork/memory-loop/`에 있습니다.

## 만료 시맨틱

`expires: YYYY-MM-DD`는 **exclusive**입니다: 메모리는 만료일 당일까지 살아
있고, 날짜가 지난 뒤 첫 세션에서 보관됩니다. `expires_when: "<이벤트>"`는
절대 자동 보관되지 않습니다 — 이벤트가 일어났을 때 에이전트(그리고 당신)가
내리는 판단의 표시입니다. 보관된 파일은 `<memory-dir>/archived/` 밑에 전체
내용이 유지됩니다. 복원은 `mv` 한 번 + 저장 게이트를 통한 재저장입니다.

## 프라이버시

완전 로컬. 아무것도 어디로도 전송되지 않습니다 — 클라우드도, 텔레메트리도,
API 키도 없습니다. identity와 습관은 언제든 읽고 고치고 지울 수 있는, 당신
머신 위의 평범한 파일입니다.

## 요구사항

- `bash` 3.2+ 와 `jq` (guardrails와 동일)

## 테스트

```bash
bats plugins/memory-loop/tests
```

커버 범위: 만료-vs-생존 경계(만료일 당일은 생존), 무태그/long/조건부/MEMORY.md
파일의 면역, 설정 우선순위, stop-hook 루프 가드, 손상된 상태에서의 fail-open.
