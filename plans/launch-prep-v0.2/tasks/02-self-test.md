# Task 02: guardrails self-test 스크립트 + 스킬

## Objective
`bash plugins/guardrails/scripts/self-test.sh` 실행 시 대표 위험명령 8+개가
시뮬레이션으로 가드를 통과하며 deny/ask 판정이 표로 출력된다(실행 0건).
`/guardrails:self-test` 스킬이 이를 안내·실행한다.

## Wiki pages
- wiki/platforms/shells/portable-shell-scripts.md — bash 3.2 호환·quoting
- wiki/platforms/tools/bsd-vs-gnu-cli.md — mac/linux 양쪽 동작

## Inputs
- plugins/guardrails/hooks/bash-guard.sh (v0.1)
- Decisions: D1(주입 방식), D6(규약)

## Steps
1. `scripts/self-test.sh`: 케이스 배열(명령|기대판정) → jq로 `{tool_input:{command}}` 생성 → bash-guard.sh stdin 주입 → permissionDecision 파싱 → ✓/✗ 표 + 요약. exit 0=전부 기대일치.
2. `skills/self-test/SKILL.md`: frontmatter(name self-test, description 트리거) + "이 스크립트를 실행하고 결과 표를 보여줘라, 명령은 절대 직접 실행하지 마라".
3. `tests/self-test.bats`: 성공 실행·exit 0·"deny" 문자열 포함 검증.

## Deliverables
- plugins/guardrails/scripts/self-test.sh
- plugins/guardrails/skills/self-test/SKILL.md
- plugins/guardrails/tests/self-test.bats

## Verify
- `bash plugins/guardrails/scripts/self-test.sh` → 전 케이스 기대일치, exit 0.

## Out of scope
- 데모 녹화 시나리오(T04).
