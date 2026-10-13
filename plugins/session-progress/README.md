# session-progress

**English** | [한국어](README.ko.md)

**See what your Claude Code session is doing, without scrolling the transcript.**
A plan bar for the current request, a history of every task with its steps and
subagents, the live progress of a dev-loop orchestration run, and a pixel dragon
that grows with your context window, so you notice before it fills up.

It is a *mod*: a plugin of function hooks that draws its own pane in the
terminal. It reads; it never writes to your project.

## Install

```text
/plugin marketplace add choiyounggi/groundwork
/plugin install session-progress@groundwork
```

The pane opens on its own in a wide terminal (see `openPaneOnStart`);
`/progress` opens it any time.

**Requires a Claude Code build with mod support.** Verified on 2.1.296; the mod
API moves between releases, so an older build may not load it.

## What it shows

```text
Plan (this task)
████████████████████████░░░░░░ 4/5 (80%)
✔ Read the config
✔ Patch the parser
⠙ Running the tests

dev-loop run · ~/src/app
███████████████████░░░░░░░░░░░ 64% overall · 3 workers
▸ task-1 ██████████░░░░░░░░░░ 50% implementing · gates 1/2 · 40s ago
▸ task-2 █████████░░░░░░░░░░░ 43% rework · try 2 · 1m 5s ago
▸ task-3 ████████████████████ 100% done · 3m 2s ago

History (2) · press a task to unfold its plan
▸ ✔ #1 Bump the dev-loop pin                           3/3 · 1m 2s
▸ ⠙ #2 Fix the flaky upload test                       running 3m 10s

        ▄▀▀▄  ▄▀▀▀▀▀▀▀            Context Dragon Lv.2
        ▀▀▀▀▀▀▀▀▀▀▀▀▀             context 21% · 210k/1.0M
      ▀▀▄ ▀▀▀▀▀▀▀▀▀▀▀             → Lv.3 ███████░░░
       ▀▀▀▀▀▀▀▀▀▀▀▀▀▄             Peep… no, ROAR?
        ▀▀▀▀▀▀▀▀▀▀▀▀              [ Regrow ]
```

- **Plan bar** follows `TodoWrite` / `TaskCreate` when your session has them.
  When it has neither, the plugin registers a small `steps` tool and asks the
  model to report 2-7 steps per request (see `reportSteps`).
- **History** keeps up to 200 tasks of this session: steps, duration, and the
  subagents each task started. Press a task to unfold it.
  Long prompts get a short title from a one-off Haiku call (see
  `summarizeTitles`).
- **dev-loop run** appears only in the coordinator's checkout of a
  [dev-loop](https://github.com/choiyounggi/dev-loop) orchestration: it reads
  `.orchestration/graph.json`, `.orchestration/status/<task>.json` and each
  worker's `.dev-loop/gates/<task>.md`. Worker sessions and repos without a run
  show nothing here. Without dev-loop the section never appears.
- **Context Dragon** reads the session's context usage and moves through seven
  stages, from egg (under 10%) to the last form (85% and up). **Regrow** runs a
  compaction and the dragon shrinks back to what the summary left; pressed
  during a task, it waits for the task to end.

## Configure

`/config` lists these under `session-progress`; they are stored in
`settings.json` under `pluginConfigs`.

| Option | Default | What it does |
|---|---|---|
| `language` | `auto` | `auto` follows Claude Code's `language` setting, then the locale (`LC_ALL`, else `LANG`); `en` or `ko` pins it. |
| `openPaneOnStart` | `true` | Open the pane when an interactive session starts. Off: only `/progress` opens it. |
| `reportSteps` | `true` | In sessions without `TodoWrite` / `TaskCreate`, register the `steps` tool and add its one-paragraph guide to the system prompt. |
| `summarizeTitles` | `true` | Shorten long prompts into history titles with a Haiku call (60 tokens out, at most one at a time). |
| `showDragon` | `true` | Draw the Context Dragon. Off: the pane shows a one-line context gauge and the dragon's animation never runs. |

The step guide is added to the system prompt. If something in your setup keeps
plugins out of the system prompt, the guide rides on each prompt's context
instead; the model reads it, you never see it.

## Cost

With the pane closed, only slow polls run: subagents every 2 s, a dev-loop run
every 5 s, and a title queue every 1.5 s (when `summarizeTitles` is on). With the
pane open, the dragon ticks every 140 ms but repaints only when its frame
changes, and the history spinner runs only while a task does. Measured on a
14-core Mac with the pane open and the session idle, the plugin adds about 2.5%
of one core over a session without it, most of it the dragon's tick;
`showDragon: false` turns that tick off.

## Develop

```bash
claude plugin validate plugins/session-progress
claude plugin test plugins/session-progress
# the dev-loop fixture is generated from dev-loop's own scripts:
bash plugins/session-progress/scripts/dev-loop-fixture.sh <dev-loop checkout> <scratch dir> \
  > plugins/session-progress/tests/fixtures/dev-loop-run.ts
```

CI regenerates that fixture against the dev-loop version pinned in
`.claude-plugin/marketplace.json` and fails when it differs, so a dev-loop
release that changes the status format turns this job red on the next run after
the pin moves.
