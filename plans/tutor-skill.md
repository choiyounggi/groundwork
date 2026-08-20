# memory-loop `tutor` skill — research-grounded design

Goal: close the "Tutor" gap in our knowledge loop. Today the flow is one-way
(capture → store → recall by the LLM); nothing ever tests whether 영기 has
actually internalized the lessons in HABITS.md. This adds the reverse flow:
spaced, diagnostic self-quizzing on distilled lessons.

## Research insights driving the design

Learning science (sources: retrieval-practice meta-analyses g≈0.5–0.6; Bjork
desirable difficulties; FSRS/SM-2 literature):

1. **Free recall > recognition.** Short-answer/free-text is the primary
   format; MCQ only as warm-up. MCQ-only success is a weak mastery signal
   (fluency illusion).
2. **Transfer questions beat restatement.** The highest-value item applies a
   lesson to a NOVEL scenario, not the original incident that produced it.
3. **Diagnose → ask → evaluate.** LLM tutors that first infer what the user
   misunderstands before generating the next question beat single-pass
   Socratic riffing (82% win rate in blind A/B, ACM 2025).
4. **Simple scheduler is enough at our scale.** For <100 items, fixed
   expanding intervals (1d/3d/7d/21d/60d, Leitner-style) are defensible;
   FSRS's edge needs review-history volume we don't have. BUT log every
   review in FSRS-compatible shape (`item_id`, `rating` 1–4, ISO timestamp)
   so a later FSRS upgrade needs no migration.
5. **Performance ≠ learning.** Same-session repeat-until-correct never counts
   as mastery; an item advances only on a correct answer after a spaced delay.
6. **Retirement rule.** 3 consecutive correct reviews at intervals ≥21d →
   maintenance tier (rare review), freeing budget for weak items.
7. **Burnout cap.** Small curated queue: hard cap per session (default 3
   items), due-date priority. Overquizzing is the top real-world
   abandonment cause.

LLM-tutor implementation practice (sources: Khanmigo, ChatGPT Study Mode,
Claude Learning Mode, claude-tutor/study-skills/socrates-skill on GitHub,
rubric-grading papers, Science 2026 sycophancy study):

8. **One question at a time, never leak the answer** before the user commits
   to an attempt. Follow up with "why / what would happen if" even on correct
   answers — correctness alone doesn't certify understanding.
9. **Item curation stays human-anchored.** LLM mass-generation of quiz items
   from raw notes produces ~36% structurally-flawed cards and removes the
   effortful-encoding benefit (user-authored beats AI-premade, d=0.45). Our
   mitigation: items derive ONLY from HABITS.md entries (already
   human-distilled, user-approved lessons) — never bulk-scraped from memory
   files. Item creation is shown to the user for veto at generation time.
10. **Anti-sycophancy grading.** Grade against the model answer/rubric held
    privately; state the misconception diagnosis BEFORE the verdict; never
    praise a wrong or partial answer; if genuinely ambiguous, say "unclear —
    tell me more" instead of forcing a verdict. (Models affirm users ~49%
    more than human raters would — Science, Mar 2026.)

## What to build (memory-loop plugin, groundwork repo)

Scope is deliberately minimal — one skill + one helper script + one hook.

### 1. `skills/tutor/SKILL.md`
Frontmatter: `name: tutor`, description with "Use when..." triggers
(퀴즈, 복습, quiz me, tutor, 테스트해줘, and the due-reminder follow-up).

Flow:
- **Sync items**: diff HABITS.md entries against `items.json`; propose new
  quiz items for entries not yet covered (show to user; user can veto/edit —
  insight #9). An item stores: `id`, `source` (habit entry text hash/ref),
  `concept` (one line), `model_answer` (the rubric), `box` (0–4),
  `due` (ISO date), `streak_ge_21d` (int), `retired` (bool).
- **Select due items**: via helper script (deterministic date math, not LLM
  arithmetic). Cap 3/session (configurable `tutorSessionCap`).
- **Quiz loop per item** (insights #1–3, #8): generate a NOVEL-scenario
  transfer question from the concept (never the original incident); ask ONE
  question, wait; grade against `model_answer` — diagnosis before verdict,
  no praise for wrong answers (insight #10); one "why"-follow-up even when
  correct; then record rating 1–4 (1 wrong / 2 hard / 3 good / 4 easy).
- **Record**: append FSRS-shaped line to `reviews.jsonl`; helper script
  advances box/due (intervals 1d/3d/7d/21d/60d; rating 1 → box 0;
  retirement per insight #6).
- Same-session retry allowed for learning but never advances the box
  (insight #5).

### 2. `skills/tutor/scripts/tutor-schedule.sh`
Bash 3.2 + jq, fail-open, conventions identical to existing hooks.
Subcommands: `due` (list due item ids, capped), `record <id> <rating>`
(append review, advance/reset box, set next due, apply retirement rule),
`sync-check` (list HABITS.md entries lacking items — text handled by skill).
State: `~/.claude/groundwork/memory-loop/tutor/{items.json,reviews.jsonl}`.
Config: existing precedence chain (`~/.claude/groundwork/memory-loop.json`
< `<cwd>/.groundwork/memory-loop.json`), keys `tutorSessionCap` (default 3),
`tutorEnabled` (default true).

### 3. `hooks/tutor-due-check.sh` (SessionStart)
Mirrors existing hook conventions (stdin JSON, jq, `set -uo pipefail`,
fail-open exit 0, no /tmp). If `tutorEnabled` and ≥1 item due, emit ONE
context line: "memory-loop tutor: N개 복습 항목이 대기 중 — '/memory-loop:tutor'
로 복습". No blocking, no nagging counter (burnout insight #7). Wire into
`hooks/hooks.json` SessionStart list.

### 4. Tests (bats, `tests/`)
Follow existing patterns (sandboxed `$HOME`, fail-open branches, config
precedence). Files: `tutor-schedule.bats` (due/record/box math/retirement/
rating-1 reset/empty state/corrupt JSON/cap/config override),
`tutor-due-check.bats` (due vs none, disabled config, malformed input).
Quality bar per instructions.md: 정상 + 에러 + 경계값 each.

### 5. Docs + release
README.md / README.ko.md skill tables + tutor section; HABITS.md template
gets no change (items reference entries, template stays authoritative).
Version: memory-loop 1.0.0 → 1.1.0 in plugin.json AND marketplace.json.
Commit convention `feat(memory-loop): ...`, release
`chore(release): groundwork X.Y.Z — ...`.

## Out of scope (YAGNI, revisit later)
- FSRS optimizer / trainable parameters (need review-log volume first).
- Quizzing dev-loop wiki pages (wiki is LLM-reference, not human-memorization
  material; HABITS.md is the human-behavior layer — right first target).
- MCQ generation, HTML quiz artifacts, Stop-hook nudges.
