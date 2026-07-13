# Task 03: README 보강 (비교표·확장성·Q&A)

## Objective
루트 README에 ① 비교표(내장 permission vs cloud guardrails vs groundwork)
② "Bring your own wiki / tests" 확장성 섹션 ③ 회의론자 Q&A 3문항이 추가되고,
guardrails README에 self-test 사용법이 추가된다.

## Inputs
- docs/launch/yolo-finding.md (T01 결과 — yolo 문구는 이 결과대로만)
- Decisions: D4(비교표 근거·사실만), D5(날조 금지)

## Steps
1. 루트 README: "Why not just …?" 섹션을 비교표로 확장(행: zero-config 기본차단, 규칙별 off/ask/block, 팀 공유 config, 감사로그+redact, 로컬 전용(데이터 미전송), 테스트/CI). rulebricks는 이름 대신 "cloud-based guardrail services"로 일반화 표기.
2. 확장성 섹션: dev-loop `configure`의 capability-role(verify=내 테스트 명령, knowledge=내 위키 MCP, tacit/explore/design) 매핑 소개 + 번들 위키가 knowledge-flush로 성장함 1줄.
3. Q&A: "CC가 이미 물어보는데?" / "그냥 settings.json permissions로 되잖아?" / "yolo 모드에선?"(T01 결과 문구).
4. guardrails README: Self-test 섹션(`/guardrails:self-test` + 수동 실행법).

## Deliverables
- README.md, plugins/guardrails/README.md (수정)

## Verify
- 표·섹션·Q&A 존재, yolo 문구가 T01 판정과 일치, 과장 문구 0.

## Out of scope
- 포스트 본문(T05).
