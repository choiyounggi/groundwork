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
# Rule ids: curl_pipe_shell curl_pipe_interp disk_destroy fork_bomb rm_rf
#   git_force_push git_reset_hard git_discard sql_drop kubectl_delete
#   sensitive_file cloud_delete secret_export worktree_escape
#   system_tmp_write(off by default)
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
# Resolve the script dir absolutely so sourcing works regardless of how the hook
# is invoked (relative $0, different $PWD); fall back to a bare dirname.
GUARD_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || GUARD_DIR="$(dirname "$0")"
# shellcheck source=/dev/null
. "$GUARD_DIR/redact.sh"

GLOBAL_CFG="${HOME}/.claude/groundwork/guardrails.json"

# Repo config: the nearest .groundwork/guardrails.json at or above $PWD, not past
# the git toplevel. A worker that cd'd into a subdirectory still finds its
# worktree config (discovery is not limited to the literal $PWD).
find_repo_cfg() {
  local d="$PWD" top
  top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  # Not in a git repo: only the literal $PWD (original behavior). Do NOT walk up
  # into unrelated parent directories, or an ancestor's config could silently
  # loosen policy for a plain directory.
  if [ -z "$top" ]; then
    [ -f "$PWD/.groundwork/guardrails.json" ] && printf '%s' "$PWD/.groundwork/guardrails.json"
    return 0
  fi
  # In a git repo: nearest config from $PWD up to (and including) the toplevel.
  while :; do
    if [ -f "$d/.groundwork/guardrails.json" ]; then
      printf '%s' "$d/.groundwork/guardrails.json"; return 0
    fi
    [ "$d" = "$top" ] && break
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
  return 0
}
REPO_CFG=$(find_repo_cfg)

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

# Per-rule path allowlist: repo config > global config, first non-empty wins
# (same precedence as effective_mode). Currently honoured by worktree_escape.
# Generic on purpose — the guard ships no knowledge of any tool's directory
# layout; a caller that has a sanctioned write path declares it in its config.
rule_allow_paths() {
  # $1 = rule id -> prints one relative path per line (may be empty)
  local id="$1" v cfg
  for cfg in "$REPO_CFG" "$GLOBAL_CFG"; do
    [ -f "$cfg" ] || continue
    v=$(jq -r --arg r "$id" '(.rules[$r].allowPaths // []) | .[]' "$cfg" 2>/dev/null)
    if [ -n "$v" ]; then printf '%s\n' "$v"; return 0; fi
  done
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

# curl|shell — remote content piped into a shell: stdin is always code → block.
# Case-insensitive (macOS FS resolves BASH→bash) and tolerant of a path prefix
# (/bin/bash). Wrapper bypasses (env/xargs/…) are out of scope — this is a
# tripwire, not a sandbox.
if imatch "${PRE}(curl|wget|fetch)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?([^[:space:];&|]*/)?(sh|bash|zsh|ksh|dash)([[:space:]]|-|<|\$)"; then
  fire curl_pipe_shell block "원격 스크립트를 셸로 바로 실행(curl|sh)하는 패턴 — 공급망 공격 위험. 파일로 받아 내용을 확인한 뒤 실행하세요."
fi

# curl|interpreter — python/node/ruby/perl reading the pipe. With -c/-e the pipe
# is DATA and the code is local & visible → ask (still eval-capable, not a free
# pass). Without, stdin is the program itself → block (same risk as curl|sh).
if imatch "${PRE}(curl|wget|fetch)[[:space:]].*\|[[:space:]]*(sudo[[:space:]]+)?([^[:space:];&|]*/)?(python[0-9.]*|node|ruby|perl)([[:space:]]|-|<|\$)"; then
  if imatch "\|[[:space:]]*(sudo[[:space:]]+)?([^[:space:];&|]*/)?(python[0-9.]*|node|ruby|perl)[[:space:]]+([^|]*[[:space:]])?-(c|e)([[:space:]]|=|'|\"|\$)"; then
    fire curl_pipe_interp ask "curl 데이터를 인터프리터의 -c/-e 스크립트로 처리 — 로컬 코드는 보이지만 eval 가능성이 남습니다. 스크립트 내용을 확인하세요."
  else
    fire curl_pipe_shell block "원격 콘텐츠를 인터프리터에 stdin 프로그램으로 실행 — 공급망 공격 위험. 파일로 받아 확인 후 실행하세요."
  fi
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

# worktree_escape — a write into the MAIN worktree from a LINKED worktree. An
# orchestration worker should stay in its own worktree; writing into the shared
# main checkout corrupts it. Best-effort and default `ask`: git is consulted only
# when the command contains an absolute path, and the match is heuristic (an
# absolute mention of the main root together with a write verb / redirect).
case "$CMD" in
  */*)
    wt_top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$wt_top" ]; then
      common=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
      case "$common" in
        */.git) main_root=$(cd "$(dirname "$common")" 2>/dev/null && pwd -P || echo "") ;;
        *)      main_root="" ;;
      esac
      wt_top_p=$(cd "$wt_top" 2>/dev/null && pwd -P || printf '%s' "$wt_top")
      # A linked worktree usually lives UNDER the main root (…/.worktrees/x), so
      # its own paths also contain main_root. Strip references to this worktree
      # first, then a remaining main_root mention is a write OUTSIDE the worktree.
      if [ -n "$main_root" ] && [ "$main_root" != "$wt_top_p" ]; then
        rest=${CMD//"$wt_top_p"/}
        # Sanctioned write paths inside the main root (rules.worktree_escape
        # .allowPaths). Strip those references too, so a command whose ONLY
        # main-root mention is a declared channel does not fire — while one that
        # also touches the checkout still does. An orchestrator's shared state
        # (status/escalation files) lives in the main worktree by design; without
        # this, every coordination write reads as checkout corruption.
        while IFS= read -r ap; do
          [ -n "$ap" ] || continue
          case "$ap" in /*|*..*) continue ;; esac   # relative, no traversal
          ap=${ap%/}
          # Build the pattern in its own variable first. In `${v//"a/b"/}` bash
          # 3.2 takes the quoted `/` as the pattern/replacement delimiter, so the
          # inline form silently becomes "replace $main_root with $ap/".
          ap_pat="$main_root/$ap"
          rest=${rest//"$ap_pat"/}
        done <<EOF
$(rule_allow_paths worktree_escape)
EOF
        # require a path separator after main_root so a sibling like
        # "<main_root>-backup/…" is not a false positive
        case "$rest" in
          *"$main_root"/*)
            if match "(^|[[:space:];&|(])(rm|mv|cp|tee|mkdir|touch|install|dd)[[:space:]]" \
               || match "(>|>>)[[:space:]]*[\"']?/"; then
              fire worktree_escape ask "링크된 워크트리에서 메인 워크트리(${main_root})에 쓰기를 시도합니다 — 워커가 공유 메인 체크아웃을 오염시킬 수 있습니다."
            fi
            ;;
        esac
      fi
    fi
    ;;
esac

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
