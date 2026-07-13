# Task 04: asciinema 데모 시나리오

## Objective
`docs/demo/`에 ① 녹화 절차 문서 ② 녹화용 실행 스크립트가 있어, 영기가
asciinema/터미널 녹화를 5분 내 뜰 수 있다.

## Inputs
- plugins/guardrails/scripts/self-test.sh (T02)

## Steps
1. `docs/demo/README.md`: 두 트랙 — (a) 안전·결정적: self-test.sh 녹화(30초), (b) 라이브: 실제 claude 세션에서 `curl … | sh` 요청 → deny 화면 캡처 절차 + 주의(실명령 위험 없음 확인).
2. `docs/demo/record-demo.sh`: 타이틀 배너 → sleep 페이싱 → self-test 실행. asciinema rec 안내 주석.

## Deliverables
- docs/demo/README.md, docs/demo/record-demo.sh

## Verify
- `bash docs/demo/record-demo.sh` 정상 종료(exit 0).

## Out of scope
- GIF 파일 생성(영기 수동).
