---
name: identity
description: Set, change, or decline the user/assistant names that memory-loop injects at session start. Use when the user wants to set up names, rename either party, ask the assistant to pick its own name, or stop the name-setup offer from appearing.
---

# memory-loop: identity

Names live in one local file the SessionStart hook reads:

```
~/.claude/groundwork/memory-loop/identity.json
```

Schema:

```json
{
  "userName": "Sam",
  "assistantName": "Iris",
  "chosenBy": "user",
  "status": "set"
}
```

- `chosenBy`: `"user"` (the user named the assistant) or `"assistant"` (the
  assistant chose its own name). When it is `"assistant"`, the hook adds
  "You chose this name yourself." to the injected context.
- `status`: `"set"` or `"declined"`.

## Set

1. Ask what the user would like to be called.
2. For the assistant's name, offer both paths and let the user pick the *path*:
   - the user names the assistant → record `chosenBy: "user"`;
   - the assistant chooses its own name and explains why it chose it →
     record `chosenBy: "assistant"`. Choose something you actually mean —
     this name persists across sessions.
3. Confirm both names with the user **before** writing anything.
4. Write the file (create the directory first):
   ```bash
   mkdir -p ~/.claude/groundwork/memory-loop
   ```
   then write the JSON above with the confirmed values and `status: "set"`.
5. Echo the resulting names back so the user sees exactly what future sessions
   will inject.

## Change

Read the current file, update only the fields the user asked to change, keep
the rest as-is, and confirm before writing.

## Decline

If the user does not want names, write exactly:

```json
{ "status": "declined" }
```

and tell them the offer will never appear again — they can opt back in any
time by invoking this skill.

## Hard rule

Never write identity.json without the user's explicit confirmation of the
values. This file speaks as context in every future session; a wrong or
unwanted name is a persistent annoyance, not a cosmetic bug.
