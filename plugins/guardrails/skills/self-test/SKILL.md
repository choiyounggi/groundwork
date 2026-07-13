---
name: self-test
description: Prove the guardrails Bash guard is live — runs a simulation that feeds representative dangerous commands (curl|sh, rm -rf, DROP TABLE, kubectl delete, cloud deletes, …) through the real guard and shows the block/ask decision for each, WITHOUT executing any of them. Use when asked to "test guardrails", "is the guard working", "guardrails self-test", or right after installing guardrails.
---

# guardrails: self-test

Run the bundled self-test to show the guard is active. It injects dangerous
command **strings** into the guard as hook data and prints each decision — it does
**not** execute any command.

## Do this

1. Run:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/self-test.sh"
   ```
2. Show the user the output table verbatim.
3. Summarize: block-tier commands were denied, ask-tier would prompt, harmless
   commands passed — and **nothing was executed**.

## Hard rule
Never run any of the dangerous example commands yourself. The whole point is that
they travel through the guard as data, never to a real shell. If the script exits
non-zero, report which case mismatched — do not "fix" it by running commands.
