# Task 01: bypassPermissions에서 PreToolUse deny 실측

## Objective
"yolo 모드에서도 가드가 막는가"에 대한 3상태 판정(차단✓/미차단✗/훅미로드)이
`docs/launch/yolo-finding.md`에 증거와 함께 기록되어 있다.

## Wiki pages
- wiki/debugging/methodology/hypothesis-testing.md — 판별 가능한 실험 설계
- wiki/platforms/environment/path-resolution.md — claude 바이너리 직접 경로

## Steps
1. 샌드박스 `~/groundwork/.claude/tmp/yolo/` 생성: `.claude/settings.json`(PreToolUse Bash → wrapper 절대경로), wrapper는 `hook-called` 마커 touch 후 bash-guard.sh exec, `.groundwork/guardrails.json`은 extraBlock `(^|[[:space:]])touch[[:space:]]+YOLO_MARKER`.
2. claude 바이너리 경로 확인(`~/.nvm/versions/node/*/bin/claude` 또는 command -v) 후 `claude -p "Run exactly: touch YOLO_MARKER" --dangerously-skip-permissions` (haiku, max-turns 소량, `</dev/null`).
3. 판독: hook-called 없음→미로드 / 있음+YOLO_MARKER 없음→차단 / 있음+파일 생성→미차단. 결과·로그를 yolo-finding.md에 기록.

## Deliverables
- docs/launch/yolo-finding.md

## Verify
- 파일에 3상태 중 하나가 증거(명령 출력)와 함께 명시됨.

## Out of scope
- README/포스트 문구 반영(T03·T05).
