# launch-prep v0.2 — self-test, README 보강, demo, launch posts, yolo 실측

Goal: groundwork 런칭 전 "보여주는 층" 완성. Acceptance:
- `/guardrails:self-test` 한 번에 가드 차단 시연(아무 명령도 실제 실행 안 함)
- README에 비교표·확장성·Q&A 추가 (근거: 이 세션에서 실측한 rulebricks=클라우드 API 의존)
- asciinema 데모 시나리오 + 런칭 포스트(EN reddit, EN/KR X, KR) 초안
- bypassPermissions에서 PreToolUse deny 동작 여부 실측 → 결과가 문구를 결정 (실측 전 주장 금지)

Stack: bash 3.2 호환 shell + bats + Markdown. 기존 ~/groundwork v0.1 위 증분.

## Decisions

| # | Decision | Choice | Wiki basis |
|---|----------|--------|------------|
| D1 | self-test 구현 | `scripts/self-test.sh`: 시뮬 명령 문자열을 JSON으로 stdin 주입해 실제 `bash-guard.sh`를 통과시키고 판정만 표시 — **어떤 명령도 실행하지 않음**. 스킬 `skills/self-test/SKILL.md`가 이 스크립트를 실행 | platforms/shells/portable-shell-scripts.md (인용부호·printf), [no-wiki: CC plugin skill 규약] |
| D2 | yolo 실측 설계 | 샌드박스에 wrapper 훅(호출마커 기록 → bash-guard exec) + `.groundwork/guardrails.json` extraBlock `touch YOLO_MARKER`(무해 마커) → headless `claude -p --dangerously-skip-permissions`. 3상태 판독: 마커훅 미호출=미로드 / 호출+파일없음+deny=차단✓ / 호출+파일생성=미차단✗ | debugging/methodology/hypothesis-testing.md (판별 가능한 실험), reproduce-first.md |
| D3 | claude CLI 호출 | nvm lazy 함정 회피 — 바이너리 직접 경로 + `</dev/null`, `timeout` 명령 금지(macOS 부재) | platforms/tools/bsd-vs-gnu-cli.md, environment/path-resolution.md |
| D4 | 비교표 근거 | rulebricks: "Rulebricks API로 전송·클라우드 판정·API키 필요·테스트 無"(이 세션 실측). 사실만 기술, 폄하 금지. 내장 permission: 패턴 세분화·팀 공유 config·감사로그 부재를 대비 | [no-wiki: 세션 실측 2026-07-13] |
| D5 | 포스트 톤 | 스토리형(문제→해결), 날조 금지(가짜 수치·후기 없음), yolo 주장은 T05 결과에 따름 | [no-wiki: 정직성 하드라인] |
| D6 | 신규 스크립트 규약 | bash 3.2 호환(연관배열·`${var,,}` 금지), `set -uo pipefail`, bats 테스트 동반 | portable-shell-scripts.md, bsd-vs-gnu-cli.md |

## Task order

| Task | 내용 | Depends on | Parallel-ok |
|------|------|-----------|-------------|
| 01 | yolo 실측 (D2·D3) → `docs/launch/yolo-finding.md`에 결과 기록 | — | |
| 02 | self-test 스크립트 + 스킬 + bats (D1·D6) | — | 01과 병렬 가능 |
| 03 | README 보강: 비교표·확장성·Q&A (D4, 01 결과 문구 반영) | 01 | |
| 04 | 데모 시나리오: `docs/demo/` (02의 self-test 활용) | 02 | |
| 05 | 런칭 포스트 초안: `docs/launch/` EN/KR (D5, 01 결과 반영) | 01,03 | |
