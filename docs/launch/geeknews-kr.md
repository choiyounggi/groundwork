# GeekNews (news.hada.io) 제출 초안

## 제목
groundwork — Claude Code용 안전 가드레일 (로컬 전용, yolo 모드에서도 작동, MIT)

## URL
https://github.com/choiyounggi/groundwork

## 요약 (본문)

Claude Code를 `--dangerously-skip-permissions`(yolo)로 돌리면 확인 프롬프트가 사라져
편하지만, 그 프롬프트가 유일한 안전장치라 에이전트가 `curl | sh`·`rm -rf` 같은 위험
명령을 그대로 실행할 수 있음.

**guardrails**는 PreToolUse 훅으로 이걸 막는 작은 플러그인:

- **차단**: `curl|sh`(공급망), `dd`/`mkfs`(디스크 파괴), fork bomb
- **확인**: `rm -rf`, force-push, `DROP`/`TRUNCATE`, `kubectl delete`, `~/.aws/credentials`·`.env` 접근, 클라우드 자원 삭제
- **감사로그**: 명령 기록 시 토큰·비밀번호 자동 마스킹
- 규칙별 `off`/`ask`/`block` + 사용자 정의 정규식 (repo/전역 설정)

특징:
- **완전 로컬** — 명령이 기기 밖으로 나가지 않음 (클라우드 판정 서비스와 달리 API 전송 없음)
- **yolo 모드에서도 작동** — headless로 실측: 프롬프트를 꺼도 PreToolUse `deny`가 명령을 막음
- 설치 후 `/guardrails:self-test`로 10초 만에 동작 확인 (위험 명령을 가드에 데이터로 흘려 판정만 표시, 실행 0건)
- bats 테스트 + CI, MIT

같은 마켓플레이스에 `dev-loop`(위키 기반 plan→verify 루프)도 함께 제공하지만 가드는 단독
사용 가능.

```
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
```
