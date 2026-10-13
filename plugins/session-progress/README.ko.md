# session-progress

[English](README.md) | **한국어**

**트랜스크립트를 거슬러 올라가지 않아도 Claude Code 세션이 지금 무엇을 하는지 보입니다.**
지금 요청의 계획 진행 바, 단계와 서브에이전트까지 담은 작업 이력, dev-loop
오케스트레이션 실행의 실시간 진행률, 그리고 컨텍스트 창과 함께 자라는 픽셀 용을
pane 하나에 보여 줍니다. 용이 커지는 걸 보고 컨텍스트가 차기 전에 알아챌 수 있습니다.

함수 훅으로 된 플러그인, 즉 *mod* 이며 터미널에 자기 pane 을 그립니다. 읽기만 하고
프로젝트에는 아무것도 쓰지 않습니다.

## 설치

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install session-progress@groundwork
```

넓은 터미널에서는 pane 이 저절로 열리고(`openPaneOnStart` 참고), `/progress` 로
언제든 열 수 있습니다.

**mod 를 지원하는 Claude Code 빌드가 필요합니다.** 2.1.296 에서 확인했습니다. mod
API 는 릴리스마다 바뀌므로 그보다 오래된 빌드에서는 로드되지 않을 수 있습니다.

## 보여 주는 것

```text
할 일 진행률 (지금 작업)
████████████████████████░░░░░░ 4/5 (80%)
✔ 설정 읽기
✔ 파서 수정
⠙ 테스트 돌리는 중

오케스트레이션 · ~/src/app
███████████████████░░░░░░░░░░░ 전체 64% · 워커 3개
▸ task-1 ██████████░░░░░░░░░░ 50% 구현 중 · 게이트 1/2 · 40초 전
▸ task-2 █████████░░░░░░░░░░░ 43% 재작업 · 시도 2 · 1분 5초 전
▸ task-3 ████████████████████ 100% 완료 · 3분 2초 전

작업 이력 (2건) · 작업을 누르면 계획 단계가 펼쳐집니다
▸ ✔ #1 dev-loop 핀 올리기                              3/3 · 1분 2초
▸ ⠙ #2 업로드 테스트 간헐 실패 수정                     진행 중 3분 10초

        ▄▀▀▄  ▄▀▀▀▀▀▀▀            컨텍스트 드래곤 Lv.2
        ▀▀▀▀▀▀▀▀▀▀▀▀▀             컨텍스트 21% · 210k/1.0M
      ▀▀▄ ▀▀▀▀▀▀▀▀▀▀▀             → Lv.3 ███████░░░
       ▀▀▀▀▀▀▀▀▀▀▀▀▀▄             삐약… 아니, 크앙?
        ▀▀▀▀▀▀▀▀▀▀▀▀              [ 다시 키우기 ]
```

- **계획 진행 바**는 세션에 `TodoWrite` / `TaskCreate` 가 있으면 그것을 따라갑니다.
  둘 다 없으면 작은 `steps` 도구를 등록하고, 요청마다 2~7개 단계를 보고하도록
  모델에게 안내합니다(`reportSteps` 참고).
- **작업 이력**은 이 세션의 작업을 최대 200개까지 보관합니다. 단계, 걸린 시간,
  그 작업이 띄운 서브에이전트가 담기고, 작업을 누르면 펼쳐집니다. 긴
  프롬프트는 Haiku 를 한 번 불러 짧은 제목으로 줄입니다(`summarizeTitles` 참고).
- **dev-loop 실행**은 [dev-loop](https://github.com/choiyounggi/dev-loop)
  오케스트레이션의 코디네이터 체크아웃에서만 나타납니다. `.orchestration/graph.json`,
  `.orchestration/status/<task>.json`, 각 워커의 `.dev-loop/gates/<task>.md` 를
  읽습니다. 워커 세션이나 실행이 없는 레포에서는 아무것도 보이지 않고, dev-loop 를
  쓰지 않으면 이 영역은 나타나지 않습니다.
- **컨텍스트 드래곤**은 세션의 컨텍스트 사용량을 읽어 7단계를 거칩니다. 10% 미만은
  알, 85% 이상은 마지막 형태입니다. **다시 키우기**는 대화를 압축하고, 용은 요약이
  남긴 크기로 되돌아갑니다. 작업 중에 누르면 그 작업이 끝난 뒤에 압축합니다.

## 설정

`/config` 의 `session-progress` 아래에 있고, `settings.json` 의 `pluginConfigs` 에
저장됩니다.

| 옵션 | 기본값 | 하는 일 |
|---|---|---|
| `language` | `auto` | `auto` 는 Claude Code 의 `language` 설정을, 없으면 로케일(`LC_ALL`, 없으면 `LANG`)을 따릅니다. `en`·`ko` 로 고정할 수 있습니다. |
| `openPaneOnStart` | `true` | 대화형 세션이 시작될 때 pane 을 엽니다. 끄면 `/progress` 로만 열립니다. |
| `reportSteps` | `true` | `TodoWrite` / `TaskCreate` 가 없는 세션에서 `steps` 도구를 등록하고, 한 문단짜리 안내를 시스템 프롬프트에 넣습니다. |
| `summarizeTitles` | `true` | 긴 프롬프트를 Haiku 호출로 작업 이력 제목으로 줄입니다(출력 60토큰, 한 번에 하나씩). |
| `showDragon` | `true` | 컨텍스트 드래곤을 그립니다. 끄면 컨텍스트 한 줄만 보이고 용 애니메이션이 돌지 않습니다. |

단계 보고 안내는 시스템 프롬프트에 들어갑니다. 환경에 따라 플러그인이 시스템
프롬프트에 닿지 못하면, 대신 프롬프트마다 context 로 붙습니다. 모델만 읽고
사람에게는 보이지 않습니다.

## 비용

pane 이 닫혀 있을 때는 느린 주기만 돕니다. 서브에이전트 2초, dev-loop 실행 5초,
제목 대기열 1.5초(`summarizeTitles` 가 켜져 있을 때)입니다. pane 이 열려 있으면 용이
140ms 마다 틱하지만 프레임이 바뀔 때만 다시 그리고, 작업 이력 스피너는 작업이 도는
동안에만 돕니다. 14코어 Mac 에서 pane 을 연 채 쉬고 있는 세션을 재 보니, 이
플러그인이 없는 세션보다 CPU 코어 하나의 약 2.5% 를 더 썼고 대부분은 용의
틱이었습니다. `showDragon: false` 로 그 틱을 끌 수 있습니다.

## 개발

```bash
claude plugin validate plugins/session-progress
claude plugin test plugins/session-progress
# dev-loop 픽스처는 dev-loop 자신의 스크립트로 만듭니다:
bash plugins/session-progress/scripts/dev-loop-fixture.sh <dev-loop 체크아웃> <작업 폴더> \
  > plugins/session-progress/tests/fixtures/dev-loop-run.ts
```

CI 는 `.claude-plugin/marketplace.json` 이 고정한 dev-loop 버전으로 이 픽스처를 다시
만들고, 달라지면 실패합니다. 그래서 상태 형식을 바꾸는 dev-loop 릴리스는 핀이 옮겨진
뒤 다음 실행에서 이 작업을 빨갛게 만듭니다.
