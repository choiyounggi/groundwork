# memory-loop

[English](README.md) | **한국어**

**Claude Code 네이티브 파일 기반 메모리를 위한 메모리 라이프사이클.**

Claude Code는 이미 메모리를 *저장*할 수 있습니다. 없는 것은 라이프사이클입니다:
사실이 검증 없이 저장되고(나중에 진실인 것처럼 회상되고), 일회성 메모가 영원히
쌓이고, 한 세션에서 배운 교훈이 다음 세션 전에 증발합니다. 이 플러그인은 저장소
둘레에 그 루프를 더합니다:

```
수집 ──────────────► 운영 ──────────────► 소멸
학습 리뷰 넛지        저장 게이트 +          만료 스윕 →
(N회 응답마다)        tier/expires,         archived/ (삭제는 절대 없음)
                     consolidate
```

그리고 라이프사이클이 있어야 가능해지는 두 가지:

- **HABITS.md** — 교정과 사고를 상시 행동으로 바꾸는 증류 프레임
  (긍정 프랙티스 🟢, 하드 라인 🛑).
- **Identity** — 사용자와 어시스턴트 *양쪽의* 이름을 정하는 1회성·거절 가능한
  제안 (어시스턴트가 자기 이름을 직접 고를 수도 있습니다). 매 세션 컨텍스트로
  주입됩니다. 이름으로 부를 수 있는 연속성.

## 설치

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install memory-loop@groundwork
```

그다음 `setup` 스킬을 실행하세요 ("set up memory-loop"라고 요청) — identity,
HABITS.md, 설정을 안내하고 훅이 응답하는지 검증합니다.

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
| `memory-expiry-sweep.sh` | SessionStart | 만료된 `tier: short` 메모리를 `archived/`로 이동(삭제 아님)하고 리포트 — 에이전트가 인덱스를 정리하고 승격을 제안하게 함 |
| `learning-nudge.sh` | Stop | N회 응답마다, 최근 작업에서 남길 가치가 있는 습관·스킬·메모리를 점검하도록 리마인드 — 각 후보는 저장 게이트를 거침 |

## 스킬

| 스킬 | 용도 |
|-------|---------|
| `setup` | 최초 세팅 안내: identity → HABITS.md → 설정 → 검증 |
| `identity` | 사용자/어시스턴트 이름 설정·변경·거절 |
| `remember` | 저장 게이트: 근거 확인 → tier 확인 → 만료 확인 → 기록 |
| `consolidate` | long-tier 메모리를 주기적으로 통합 — 중복 병합·모순은 최신 진실로 해소·날짜 절대화 — 쓰기 전 확인을 거치고, `archived/`로 보내며 삭제는 하지 않음 |
| `habit` | 교훈을 HABITS.md로 증류 (🟢 프랙티스 / 🛑 하드 라인), 증식 대신 병합, 필요 시 훅/스킬로 승격 |

## 설정

선택사항입니다. `examples/memory-loop.example.json`을
`~/.claude/groundwork/memory-loop.json`(글로벌) 또는
`<repo>/.groundwork/memory-loop.json`(레포, 팀 공유)으로 복사하세요.
레포 > 글로벌 > 내장 기본값 순으로 우선합니다.

| 키 | 기본값 | 의미 |
|-----|---------|---------|
| `nudgeInterval` | `10` | 학습 리뷰 넛지를 N회 응답마다 발화 |
| `extraMemoryDirs` | `[]` | 현재 프로젝트의 메모리 디렉토리 외에 추가로 스윕할 디렉토리 (`~` 지원) |

상태(identity, 넛지 카운터)는 `~/.claude/groundwork/memory-loop/`에 있습니다.

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
