#!/usr/bin/env bash
# groundwork / memory-loop — Identity context injection.
#
# SessionStart hook. Three-way branch on ~/.claude/groundwork/memory-loop/identity.json:
#   - file absent            -> print a one-time setup offer (ask the user's
#                               name; the assistant's name can be given by the
#                               user or chosen by the assistant itself)
#   - status == "declined"   -> print nothing, ever again
#   - both names configured  -> inject one line naming both parties
#
# Design notes (why it looks like this):
#   - stdout of a SessionStart hook is injected as session context, so names
#     work without ever editing the user's CLAUDE.md; uninstalling the plugin
#     leaves no trace in user files.
#   - Fail open: a malformed or partial identity file prints nothing and exits
#     0. It deliberately does NOT re-offer setup — a broken file must not nag
#     a user who already answered; the "identity" skill repairs it on demand.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

IDENTITY="${HOME}/.claude/groundwork/memory-loop/identity.json"

if [ ! -f "$IDENTITY" ]; then
  cat <<'EOF'
[memory-loop] No identity is configured for this machine yet.
In your first reply this session, briefly and naturally offer a one-time name setup (do not push if the user is mid-task):
  - Ask what the user would like to be called.
  - For your own name, offer both options: the user names you, or you choose a name yourself and say why you chose it.
  - Record the result with the memory-loop "identity" skill. If the user declines, record the decline so this offer never appears again.
EOF
  exit 0
fi

STATUS=$(jq -r '.status // empty' "$IDENTITY" 2>/dev/null || true)
[ "$STATUS" = "declined" ] && exit 0

USER_NAME=$(jq -r '.userName // empty' "$IDENTITY" 2>/dev/null || true)
ASSISTANT_NAME=$(jq -r '.assistantName // empty' "$IDENTITY" 2>/dev/null || true)

# Anything short of a complete pair (including parse failures) stays silent.
if [ -n "$USER_NAME" ] && [ -n "$ASSISTANT_NAME" ]; then
  LINE="The user's name is ${USER_NAME}. Your name is ${ASSISTANT_NAME}. Address each other by name."
  CHOSEN_BY=$(jq -r '.chosenBy // empty' "$IDENTITY" 2>/dev/null || true)
  if [ "$CHOSEN_BY" = "assistant" ]; then
    LINE="${LINE} You chose this name yourself."
  fi
  printf '%s\n' "$LINE"
fi
exit 0
