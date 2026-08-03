#!/usr/bin/env bash
# groundwork / guardrails — Safe-by-default Bash guard for Claude Code.
#
# PreToolUse(Bash) hook. Emits a permission decision (deny / ask) for dangerous
# shell commands; stays silent (allow) otherwise. Generic — no org-specific rules.
#
# Config precedence (git-config style): built-in default
#     < ~/.claude/groundwork/guardrails.json          (global)
#     < <cwd>/.groundwork/guardrails.json             (repo, team-shared)
# Shape: {"rules": {"<id>": {"mode": "off|ask|block"}},
#         "extraAsk": ["regex", ...], "extraBlock": ["regex", ...]}
# Rule ids: curl_pipe_shell disk_destroy fork_bomb rm_rf git_force_push
#   git_reset_hard git_discard sql_drop kubectl_delete sensitive_file
#   cloud_delete secret_export system_tmp_write(off by default)
#
# Non-interactive/CI: set GROUNDWORK_NONINTERACTIVE=1 to turn every `ask` into `deny`.
#
# Design notes (why it looks like this):
#   - Patterns anchor command words at an execution position (start, or after
#     ; & | && || ( or whitespace) so a *mention* inside a quoted argument does
#     not trigger a block. Block-tier rules are additionally specific.
#   - bash 3.2 compatible: no associative arrays, no ${var,,}.
set -uo pipefail

# Shared secret redaction — used when recording an escalation (see escalate()).
# shellcheck source=/dev/null
. "$(dirname "$0")/redact.sh"

GLOBAL_CFG="${HOME}/.claude/groundwork/guardrails.json"
REPO_CFG="${PWD}/.groundwork/guardrails.json"

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Effective mode for a rule: repo config > global config > built-in default.
effective_mode() {
  # $1 = rule id, $2 = default mode
  local id="$1" def="$2" m cfg
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    m=$(jq -r --arg r "$id" '.rules[$r].mode // empty' "$cfg" 2>/dev/null)
    if [ -n "$m" ]; then printf '%s' "$m"; return 0; fi
  done
  printf '%s' "$def"
}

escalate() {
  # $1 = rule id, $2 = original reason. Record a pending decision for the
  # coordinator (dev-loop watch reads this dir). Best-effort — any failure still
  # results in a deny, so a worker never proceeds on an unrecorded escalation.
  local id="$1" reason="$2" dir="${GROUNDWORK_ESCALATION_DIR:-}" ts tmp
  [ -n "$dir" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
  tmp="$dir/.tmp.$$-$RANDOM"
  jq -cn --arg ts "$ts" --arg task "${GROUNDWORK_TASK_ID:-}" \
    --arg rule "$id" --arg reason "$reason" \
    --arg cmd "$(redact "$CMD")" --arg cwd "$PWD" \
    '{ts:$ts, taskId:$task, rule:$rule, reason:$reason, cmd:$cmd, cwd:$cwd}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
  mv "$tmp" "$dir/$(date +%s 2>/dev/null || echo 0)-$RANDOM.json" 2>/dev/null \
    || rm -f "$tmp" 2>/dev/null
}

emit() {
  # $1 = mode (block|ask), $2 = reason, $3 = rule id (for escalation records).
  # Exits on a real decision.
  local mode="$1" reason="$2" id="${3:-custom}" pd
  case "$mode" in
    block) pd="deny" ;;
    ask)   pd="ask" ;;
    *)     return 0 ;;
  esac
  # In an orchestration worker (dev-loop exports GROUNDWORK_ESCALATION_DIR), turn
  # a blocking `ask` into an observable event: record it and deny, so the
  # coordinator sees it and can re-issue with approval. Takes precedence over
  # NONINTERACTIVE — both deny, but escalation is visible rather than silent.
  if [ "$pd" = "ask" ] && [ -n "${GROUNDWORK_ESCALATION_DIR:-}" ]; then
    escalate "$id" "$reason"
    pd="deny"
    reason="코디네이터에 에스컬레이션됨 (규칙: ${id}). 승인이 필요하면 오케스트레이터가 재실행합니다."
  elif [ "$pd" = "ask" ] && [ "${GROUNDWORK_NONINTERACTIVE:-0}" = "1" ]; then
    pd="deny"
  fi
  jq -cn --arg pd "$pd" --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $pd, permissionDecisionReason: $r}}'
  exit 0
}

fire() {
  # $1 id, $2 default mode, $3 reason — called only when a pattern matched.
  local mode
  mode=$(effective_mode "$1" "$2")
  [ "$mode" = "off" ] && return 0
  emit "$mode" "$3" "$1"
}

match() { printf '%s' "$CMD" | grep -qE "$1"; }
imatch() { printf '%s' "$CMD" | grep -qiE "$1"; }

# Command word at an execution position.
PRE='(^|[[:space:];&|(])'

# ===================== block tier (specific, low false-positive) =====================

# curl|sh — remote script piped straight into an interpreter (supply chain).
if match "${PRE}(curl|wget|fetch)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|ksh|dash|python[0-9.]*|node|ruby|perl)([[:space:]]|-|<|\$)"; then
  fire curl_pipe_shell block "원격 스크립트를 인터프리터로 바로 실행(curl|sh)하는 패턴 — 공급망 공격 위험. 파일로 받아 내용을 확인한 뒤 실행하세요."
fi

# Disk-destroying writes.
if match "(dd[[:space:]]+.*[[:space:]]of=/dev/(sd|nvme|disk|hd)|mkfs\.[a-z0-9]+[[:space:]]+/dev/|${PRE}>[[:space:]]*/dev/(sd|nvme|disk|hd))"; then
  fire disk_destroy block "디스크 장치에 직접 쓰는 명령(dd / mkfs / >/dev/…) — 복구 불가능한 데이터 손실."
fi

# Fork bomb.
if match ':[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:[[:space:]]*&[[:space:]]*\}[[:space:]]*;[[:space:]]*:'; then
  fire fork_bomb block "fork bomb 패턴이 감지되었습니다."
fi

# ===================== ask tier =====================

# rm -rf — recursive AND force (either order, clustered or split, long or short).
if imatch "${PRE}rm[[:space:]]+([^|;&]*[[:space:]])?(-[[:alnum:]]*r[[:alnum:]]*f|-[[:alnum:]]*f[[:alnum:]]*r|-[rR][[:space:]]+-[[:alnum:]]*f|-f[[:space:]]+-[[:alnum:]]*[rR]|--recursive[[:space:]].*--force|--force[[:space:]].*--recursive)"; then
  fire rm_rf ask "rm -rf (재귀 + 강제 삭제) — 되돌릴 수 없습니다. 대상 경로를 확인하세요."
fi

# git force push.
if match "git[[:space:]]+push[[:space:]].*(-f($|[[:space:]])|--force([[:space:]]|=|$))"; then
  fire git_force_push ask "force push는 원격 히스토리를 덮어씁니다."
fi

# git reset --hard.
if match "git[[:space:]]+reset[[:space:]]+--hard"; then
  fire git_reset_hard ask "git reset --hard는 커밋되지 않은 모든 변경을 삭제합니다."
fi

# git checkout/restore .  (discard working tree).
if match "git[[:space:]]+(checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)"; then
  fire git_discard ask "작업 트리의 변경을 되돌립니다 — 커밋되지 않은 작업이 유실될 수 있습니다."
fi

# SQL DROP / TRUNCATE.
if imatch "drop[[:space:]]+(table|database|schema)\b|(^|[[:space:];&|(\"'\`])truncate[[:space:]]+(table[[:space:]]+)?[a-z_\"\`]"; then
  fire sql_drop ask "DROP / TRUNCATE 는 데이터를 영구 삭제합니다."
fi

# kubectl delete.
if match "kubectl[[:space:]]+.*\bdelete\b"; then
  fire kubectl_delete ask "kubectl delete는 클러스터 리소스를 제거합니다 — 프로덕션에 영향을 줄 수 있습니다."
fi

# Sensitive file access (keys / credentials / .env).
if match "(rm|mv|cp|cat|less|more|scp|tee|curl|wget)[[:space:]].*(\.ssh/(id_|authorized_keys|known_hosts)|\.aws/credentials|\.netrc|\.npmrc|\.pgpass|(^|/)\.env($|[[:space:].]))"; then
  fire sensitive_file ask "SSH 키·클라우드 크레덴셜·.env 등 민감 파일에 접근/수정하려 합니다."
fi

# Cloud resource deletion.
if match "(aws[[:space:]]+[a-z0-9-]+[[:space:]]+(delete|terminate|rb|remove)[a-z-]*|gcloud[[:space:]]+.*[[:space:]]delete([[:space:]]|$)|(^|[[:space:]])az[[:space:]]+.*[[:space:]]delete([[:space:]]|$))"; then
  fire cloud_delete ask "클라우드 자원 삭제 명령입니다. 대상 환경(프로덕션?)과 의존성을 확인하세요."
fi

# Secret export to env (leaks into shell history).
if match "export[[:space:]]+[A-Za-z_]*(TOKEN|SECRET|API_?KEY|PASSWORD|ACCESS_KEY|PRIVATE_KEY)"; then
  fire secret_export ask "API 키/토큰을 환경변수로 설정 — 쉘 히스토리에 남을 수 있습니다. .env 파일 사용을 권장합니다."
fi

# System temp write — OFF by default. Opt in for EDR-restricted environments.
if match "${PRE}[<>]?[[:space:]]*(/tmp/|/private/tmp/|/private/var/folders/|\\\$TMPDIR)"; then
  fire system_tmp_write off "시스템 임시 디렉토리(/tmp 등)에 씁니다. 일부 EDR 정책에서 차단 대상입니다."
fi

# ===================== user-defined extra patterns =====================
apply_extra() {
  # $1 = jq array field, $2 = mode
  local field="$1" mode="$2" cfg pat
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    while IFS= read -r pat; do
      [ -z "$pat" ] && continue
      if printf '%s' "$CMD" | grep -qE "$pat"; then
        emit "$mode" "사용자 정의 가드 패턴에 매칭되었습니다: ${pat}"
      fi
    done <<EOF
$(jq -r --arg f "$field" '.[$f][]? // empty' "$cfg" 2>/dev/null)
EOF
  done
}
apply_extra extraBlock block
apply_extra extraAsk ask

exit 0
