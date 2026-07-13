# X / Twitter thread (draft) — EN + KR

## EN

**1/**
I run Claude Code with `--dangerously-skip-permissions` because the prompts kill my
flow.

Then I watched an agent reach for `curl … | sh`.

That flag turns off the only thing stopping it. So I built a net. 🧵

**2/**
**guardrails** — a PreToolUse hook that:
• blocks `curl|sh`, `dd`, fork bombs
• asks before `rm -rf`, force-push, `DROP`, `kubectl delete`, reading creds/.env
• redacted audit log (tokens masked)
• every rule off/ask/block + your own patterns

**3/**
Two things that make it different:

🔒 Fully local — commands never leave your machine (no cloud API).
🚀 Works in `--dangerously-skip-permissions` — I tested it headless: a `deny` still
stops the command when prompts are off. That's when you need it most.

**4/**
See it work in 10s after install:

`/guardrails:self-test`

It runs the dangerous commands *through the guard as data* and shows each decision —
without executing any of them. Instant proof it's live.

**5/**
Zero config. Tests + CI. MIT. Ships next to `dev-loop` (a wiki-grounded plan→verify
loop), but the guard stands alone.

```
/plugin marketplace add choiyounggi/groundwork
/plugin install guardrails@groundwork
```

github.com/choiyounggi/groundwork

What should it catch that it doesn't yet? 👇

## KR

**1/**
난 Claude Code를 `--dangerously-skip-permissions`(yolo)로 돌려. 확인 프롬프트가
흐름을 끊거든.

근데 에이전트가 `curl … | sh` 설치를 시도하는 걸 봤어. 그 플래그가 바로 그걸 막던
유일한 안전장치였는데. 그래서 그물을 만들었어. 🧵

**2/**
**guardrails** — PreToolUse 훅:
• `curl|sh`·`dd`·포크밤 차단
• `rm -rf`·force-push·`DROP`·`kubectl delete`·크레덴셜/.env 접근은 확인
• 시크릿 마스킹 감사로그
• 규칙별 off/ask/block + 커스텀 패턴

**3/**
차별점 둘:
🔒 완전 로컬 — 명령이 기기 밖으로 안 나감(클라우드 API 아님)
🚀 yolo 모드에서도 작동 — headless로 실측함. 프롬프트 꺼도 `deny`가 명령을 막아.
정작 필요한 순간에.

**4/**
설치 후 10초면 확인:
`/guardrails:self-test`
위험 명령을 *가드에 데이터로* 흘려 각 판정을 보여줘 — 실행은 0건.

**5/**
무설정·테스트·CI·MIT.
```
/plugin marketplace add choiyounggi/groundwork
```
github.com/choiyounggi/groundwork
