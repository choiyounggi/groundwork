# file-lifecycle

[English](README.md) | **한국어**

에이전트는 일회성 스크립트·중간 결과·로그·클론한 레포·리포트를 여기저기 남깁니다.
규칙이 없으면 `~/.claude/tmp` 에 쌓이기만 하고, 정작 남겨야 할 몇 개는 그 속에 묻힙니다.
file-lifecycle 은 모든 파일에 두 가지 수명 중 하나를 줍니다.

| 종류 | 위치 | 수명 |
|---|---|---|
| 임시 | `~/.claude/tmp/s/<session_id>/` (`$CLAUDE_SESSION_TMP`) | 세션이 끝나고 24시간 뒤 삭제 |
| 남길 것 | `~/claude-archive/<분류>/<YYYY-MM-DD>_<slug>` | 직접 지울 때까지 보관, `INDEX.md` 에 목록 |

```text
/plugin install file-lifecycle@groundwork
```

macOS·Linux 의 `python3`(3.8+)만 있으면 됩니다.

## 동작 방식

1. **SessionStart** — 세션 전용 임시 폴더를 만들고 Bash 에 `CLAUDE_SESSION_TMP`·`CLAUDE_SESSION_ID` 를
   내보냅니다. 컨텍스트에는 「임시 파일은 어디에, 남길 파일은 어떻게」 한 줄만 넣습니다.
2. **SessionEnd** — `.ended` 표식만 남깁니다. 실제 삭제는 유예(24시간) 뒤 정리기가 합니다.
   SessionEnd 훅은 시간 예산이 짧아 큰 폴더를 지우다 끊길 수 있고, `/clear`·재개 직후에 파일이
   다시 필요할 수 있어서입니다. 재개하면 표식이 지워집니다.
3. **정리기** — 세션 시작 때 백그라운드로 돌고, 6시간에 한 번만 돕니다. 그래서 「24시간 뒤」는
   24시간이 지난 뒤 처음 도는 정리를 뜻하고, 새 세션이 열리지 않으면 아무것도 지우지 않습니다.
   표식 없이 죽은 세션은 claude 프로세스가 없고, 트랜스크립트가 7일 넘게 멈췄고, 폴더도 7일 넘게
   안 바뀌었을 때 지웁니다. 플러그인이 만든 폴더(세션 ID 이름 + 표식 파일)만 관리하고, `s/` 아래의
   다른 폴더는 건드리지 않습니다.
4. **보관함** — `/file-lifecycle:archive` 또는 `scripts/archive.py` 가 날짜 붙은 이름으로 옮기고,
   무엇·왜를 `index.jsonl` 에 적고, 내비게이터 `INDEX.md` 를 다시 만듭니다. 에이전트는 오래 둘
   파일을 새로 만들기 전에 이 파일부터 봅니다.

## tmp 최상위 정리 (선택)

세션 폴더는 항상 관리합니다. 그 밖의 `~/.claude/tmp` 항목은 `"sweep_top_level": true` 를 켜기
전까지 건드리지 않습니다. 도구가 고정 경로에 상태(락·큐·로그 폴더)를 두는 경우가 많고, 그걸
지우는 피해가 어수선함보다 크기 때문입니다. 남길 것을 먼저 등록하고 켭니다.

```json
{
  "sweep_top_level": true,
  "entries": [
    {"pattern": "test-queue", "policy": "keep", "why": "세션들이 공유하는 테스트 큐 상태"},
    {"pattern": "launchd-logs", "policy": "ttl-contents", "ttl_days": 30, "why": "LaunchAgent 로그 폴더"},
    {"pattern": "guard-off", "policy": "ttl", "ttl_days": 1, "why": "가드 해제 표식 — 하루 뒤 자동 복원"}
  ]
}
```

- `keep` 삭제 안 함 · `ttl` 항목째 `ttl_days` 뒤 삭제 · `ttl-contents` 폴더는 두고 안의 항목만 삭제.
- 등록 안 된 항목은 `default_ttl_days`(7일) 뒤 삭제합니다. policy 가 없거나 모르는 값이면 남깁니다.
  패턴은 최상위 이름에 대한 glob 이고, 처음 맞은 항목이 적용됩니다.
- 나이는 트리 안 **가장 최근 수정 시각**과 **정리기가 처음 발견한 시각**이 **둘 다** 기준을 넘어야
  찹니다. 수정 시각만 보면 `mv`·`tar -x` 로 옛 시각을 가진 채 들어온 파일이 바로 지워지기
  때문입니다. 그래서 켠 직후에는 첫 정리부터 TTL(`default_ttl_days`, 또는 등록 항목의 더 짧은
  `ttl_days`)이 지나기 전까지 아무것도 지워지지 않습니다.
- `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/tmp_lifecycle.py" status` 는 지우지 않고 무엇이 지워질지만
  보여 줍니다. (SessionStart 컨텍스트 한 줄에 플러그인 스크립트의 전체 경로가 나옵니다.)

전체 예시: [`examples/file-lifecycle.example.json`](examples/file-lifecycle.example.json)
(`sweep_top_level: false` 로 들어 있습니다 — 항목을 내 환경에 맞춘 뒤 켭니다).
설정 파일은 `~/.claude/groundwork/file-lifecycle.json` 이고 모든 키가 선택입니다. 설정은 검사합니다 —
타입이 틀리거나(문자열 `"false"`, 글자로 쓴 숫자, 0 인 TTL) 루트가 위험하면(상대 경로, `/`, 홈 폴더,
git 체크아웃) 오류로 보고, 잘못된 설정으로는 아무것도 지우지 않습니다.

## 정리기가 절대 지우지 않는 것

- 프로세스가 열고 있거나 작업 폴더로 쓰는 항목(`lsof`). `lsof` 가 실패하거나 없으면 아무것도 지우지 않습니다.
- git 저장소(워크트리·클론·bare)가 들어 있는 항목 — 세션 폴더 안이라도. 미커밋 작업이 있을 수 있어
  로그에 `KEEP(contains git)` 으로만 남깁니다.
- claude 프로세스가 살아 있는 세션 폴더(PID + 시작 시각으로 판정 — 재사용된 PID 는 인정하지 않음).
- 심링크의 대상, tmp 루트 밖의 모든 것.
- 설정 파일이 있는데 잘못됐으면 전부. 기본값에는 `keep` 항목이 없어서, 기본값으로 정리하면
  등록해 둔 것을 지울 수 있기 때문입니다.

## 보관함

```bash
A="${CLAUDE_PLUGIN_ROOT}/scripts/archive.py"
python3 "$A" find <키워드>                 # 먼저 찾는다
python3 "$A" add <경로> --cat reports \
  --topic "무엇" --why "왜 생겼고 언제 다시 쓰나"
python3 "$A" check                         # 어긋남·검토일 경과
python3 "$A" remove <경로> --yes
```

- 분류: `reports` · `plans` · `data` · `backups` · `notes` · `scripts`.
- **시크릿 검사는 실패 시 거부(fail-closed).** 키 대입·클라우드 키·URL 자격증명·Bearer·JWT·개인키·
  Slack/GitHub 토큰·시크릿 같은 파일 이름을 일반 파일·gzip/bz2/xz·tar/zip 내부(3단계)·UTF-16 까지
  봅니다. 값은 출력하지 않고 패턴 이름만 냅니다. 검사할 수 없는 파일(5MB 초과·알 수 없는 바이너리·
  암호화 압축)은 `--allow-unscanned` 전까지 거부하고, 직접 확인한 오탐은 `--accept-hit <경로>` 로 통과시킵니다.
- 같은 내용(sha256)은 거부합니다 — 내비게이터에 같은 파일이 두 번 오르지 않게.
- 심링크는 옮기지 않습니다. `--copy` 는 실제 대상을 검사해서 복사합니다.
- 자동으로는 아무것도 지우지 않습니다. `--review` 날짜가 지나면 `check` 가 알려 줍니다.

## 테스트

```bash
python3 -m unittest discover -s plugins/file-lifecycle/tests
```

테스트 샌드박스를 시스템 임시 폴더 밖에 두려면 `FILE_LIFECYCLE_TEST_DIR` 를 지정합니다.
