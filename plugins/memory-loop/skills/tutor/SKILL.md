---
name: tutor
description: Run a spaced-repetition self-quiz over lessons already distilled into HABITS.md — one novel-scenario transfer question per due item, anti-sycophancy grading, and a 1-4 recall rating logged through the tutor scheduler. Use when the user asks to be quizzed or reviewed (English or Korean), or replies to a memory-loop tutor due-reminder line ("N개 복습 항목이 대기 중").
---

# memory-loop: tutor

`habit` distills lessons into HABITS.md; nothing before this tested whether
the user actually internalized them. This closes that loop: spaced,
diagnostic self-quizzing, driven by the merged `tutor-schedule.sh` scheduler.

## Never hand-edit state

State lives in `~/.claude/groundwork/memory-loop/tutor/{items.json,reviews.jsonl}`,
owned by `${CLAUDE_PLUGIN_ROOT}/skills/tutor/scripts/tutor-schedule.sh`. Every
state change goes through the script's subcommands — `due [--count]`,
`record <id> <rating>`, `add <id> <concept> <model_answer> <source_ref>`,
`list`. Never edit `items.json` or `reviews.jsonl` directly, even to fix a typo.

## 1. Sync items

Run `list` to see items already tracked (each carries a `source_ref`). Read
HABITS.md and diff its 🟢/🛑 entries against those `source_ref`s. For every
entry with no covered item, propose a candidate — a one-line `concept` and a
`model_answer` (the rubric: what a correct answer must cover) — and **show it
to the user before creating anything**. They can veto or edit it. Only after
their go-ahead, call `add <id> <concept> <model_answer> <source_ref>` with a
short readable `id` (e.g. a slug of the concept) not already in `list` — item
curation stays human-anchored, never bulk-generated from raw memory.

## 2. Select due items

Run `due` (already capped at `tutorSessionCap`, default 3 — don't ask for
more this session). If it prints nothing, tell the user nothing is due and
stop; don't invent a quiz just to have one.

## 3. Quiz loop — one item at a time

For each due id, in order:

1. **Ask a transfer question.** From the item's `concept`, invent ONE novel
   scenario the user hasn't seen — never restate or re-ask about the
   original incident behind the lesson. Ask it, then **wait** for the answer
   before doing anything else.
2. **Grade against `model_answer`**, held privately the whole time:
   - Diagnose the misconception (what's missing or wrong) **before** the
     verdict — never lead with "correct!"/"incorrect!".
   - Never praise a wrong or partial answer, even gently.
   - If the answer is genuinely ambiguous, say so and ask for more instead
     of forcing a verdict either way.
3. **Follow up.** Ask one "왜?" or "이게 바뀌면 어떻게 돼?" (why / what-if)
   question — even when the answer was fully correct — before moving on.
4. **Rate together.** Show this table and let the user confirm the rating —
   don't record a number they haven't seen:

   | Rating | 의미 |
   |--------|------|
   | 1 | 틀림 / 기억 안 남 |
   | 2 | 어렵게 부분 회상 |
   | 3 | 정상 회상 |
   | 4 | 즉답 |

5. On confirmation, run `record <id> <rating>`.

## Retry vs. record

The user may retry an item in the same session to keep learning from it —
that's fine for practice. But only the **first** confirmed rating for an id
gets `record`ed this session; never call `record` twice for the same id in
one sitting, no matter how many retries happened.

## Ending a session

When the due queue is empty (naturally, or the user stops early), print one
line — reviewed count, correct count (rating ≥3), and the next due date from
`list` — then stop. No auto-continuing into another round, no nagging.
