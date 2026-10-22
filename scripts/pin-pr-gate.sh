#!/usr/bin/env bash
# groundwork — the two PR steps of .github/workflows/sync-dev-loop-pin.yml that
# keep back-to-back dev-loop releases from stranding pin PRs (issue #141).
#
# The strand: main requires status checks, so `gh pr merge --auto` returns before
# the merge lands. A run dispatched in that window branched from the old main, and
# its PR edits the same two lines — once the earlier PR merged it conflicted and
# never merged, while the log still said "pinned". Every other PR of a release
# burst stayed open (#86–#107, #120–#138).
#
# Usage:
#   pin-pr-gate.sh superseded <vX.Y.Z>
#       stdin: "<number> <branch>" lines (open PRs). Prints, one per line, the
#       number of each chore/pin-dev-loop-vA.B.C PR whose tag is older than
#       <vX.Y.Z>. Other branches and malformed tags are skipped, never printed.
#   pin-pr-gate.sh wait-merged <pr> [attempts] [interval-seconds]
#       Polls the PR's state (default 80 attempts, 15s apart = 20 minutes).
#       A failed gh call is retried. PIN_GH overrides the gh binary (tests).
#
# Exit codes:
#   0  superseded: listed (possibly nothing) · wait-merged: the PR merged
#   3  wait-merged: the PR was closed without merging
#   4  wait-merged: the PR was still open after the last attempt
#   2  usage error
set -euo pipefail

usage() {
  echo "usage: pin-pr-gate.sh superseded <vX.Y.Z> | wait-merged <pr> [attempts] [interval-seconds]" >&2
  exit 2
}

is_tag() { printf '%s' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; }
is_uint() { printf '%s' "$1" | grep -Eq '^[0-9]+$'; }

# Succeeds when version tag $1 is older than $2 (both vX.Y.Z), compared numerically.
older_than() {
  local a b
  IFS=. read -r -a a <<< "${1#v}"
  IFS=. read -r -a b <<< "${2#v}"
  for i in 0 1 2; do
    [ "$((10#${a[i]}))" -lt "$((10#${b[i]}))" ] && return 0
    [ "$((10#${a[i]}))" -gt "$((10#${b[i]}))" ] && return 1
  done
  return 1
}

[ "$#" -ge 1 ] || usage

case "$1" in
  superseded)
    [ "$#" -eq 2 ] || usage
    tag="$2"
    if ! is_tag "$tag"; then
      echo "pin-pr-gate: '$tag' is not a vX.Y.Z release tag" >&2
      exit 2
    fi
    while read -r number branch; do
      [ -n "${number:-}" ] || continue
      is_uint "$number" || continue
      case "$branch" in chore/pin-dev-loop-*) ;; *) continue ;; esac
      pin="${branch#chore/pin-dev-loop-}"
      is_tag "$pin" || continue
      if older_than "$pin" "$tag"; then
        echo "$number"
      fi
    done
    ;;

  wait-merged)
    [ "$#" -ge 2 ] && [ "$#" -le 4 ] || usage
    pr="$2"
    attempts="${3:-80}"
    interval="${4:-15}"
    if ! is_uint "$pr" || ! is_uint "$attempts" || ! is_uint "$interval" || [ "$attempts" -lt 1 ]; then
      echo "pin-pr-gate: pr and attempts must be positive integers, interval a non-negative integer" >&2
      exit 2
    fi
    gh_bin="${PIN_GH:-gh}"
    state=""
    for ((n = 1; n <= attempts; n++)); do
      state=$("$gh_bin" pr view "$pr" --json state --jq .state 2>/dev/null) || state="UNKNOWN"
      case "$state" in
        MERGED) echo "merged: #$pr"; exit 0 ;;
        CLOSED) echo "pin-pr-gate: PR #$pr was closed without merging"; exit 3 ;;
      esac
      [ "$n" -lt "$attempts" ] && sleep "$interval"
    done
    echo "pin-pr-gate: PR #$pr still $state after $attempts checks"
    exit 4
    ;;

  *) usage ;;
esac
