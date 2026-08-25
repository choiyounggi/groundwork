#!/usr/bin/env bash
# groundwork — move the dev-loop marketplace pin to a released dev-loop tag.
#
# dev-loop is distributed as a TAG-PINNED url source:
#   {"source": {"source": "url", "url": ".../dev-loop.git", "ref": "vX.Y.Z"},
#    "version": "X.Y.Z"}
# Claude Code checks out exactly that ref, so a dev-loop release reaches nobody
# until BOTH fields move. This script is the mechanical half of that step; the
# workflow (.github/workflows/sync-dev-loop-pin.yml) supplies the tag and opens
# the PR. It is safe to run locally — it only rewrites the two fields.
#
# Usage: sync-dev-loop-pin.sh <vX.Y.Z> [repo-root]   (repo-root defaults to ".")
#
# Exit codes:
#   0  already in sync — nothing written
#   3  pin updated to <vX.Y.Z> (both ref and version rewritten)
#   2  usage error, bad tag format, missing/unparseable marketplace.json, or no
#      tag-pinned dev-loop entry to update
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: sync-dev-loop-pin.sh <vX.Y.Z> [repo-root]" >&2
  exit 2
fi

TAG="$1"
REPO_ROOT="${2:-.}"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

# A pin must be an exact release tag: vMAJOR.MINOR.PATCH. Anything looser (a
# branch name, a bare version, a moving ref) would silently un-pin the plugin.
if ! printf '%s' "$TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "sync-dev-loop-pin: '$TAG' is not a vX.Y.Z release tag" >&2
  exit 2
fi
VERSION="${TAG#v}"

if [ ! -f "$MARKETPLACE" ]; then
  echo "sync-dev-loop-pin: marketplace file not found: $MARKETPLACE" >&2
  exit 2
fi

if ! jq empty "$MARKETPLACE" >/dev/null 2>&1; then
  echo "sync-dev-loop-pin: unparseable JSON: $MARKETPLACE" >&2
  exit 2
fi

# The entry must already be tag-pinned. If it is not, the distribution model
# changed and a blind rewrite would be wrong — report instead of guessing.
entry_count=$(jq '[.plugins[]? | select(.name == "dev-loop") | select(.source.ref)] | length' "$MARKETPLACE")
if [ "$entry_count" != "1" ]; then
  echo "sync-dev-loop-pin: expected exactly 1 tag-pinned dev-loop entry in $MARKETPLACE, found $entry_count" >&2
  exit 2
fi

current_ref=$(jq -r '.plugins[] | select(.name == "dev-loop") | .source.ref' "$MARKETPLACE")
current_version=$(jq -r '.plugins[] | select(.name == "dev-loop") | .version // ""' "$MARKETPLACE")

if [ "$current_ref" = "$TAG" ] && [ "$current_version" = "$VERSION" ]; then
  echo "in sync: dev-loop pinned at $TAG"
  exit 0
fi

tmp="${MARKETPLACE}.tmp.$$"
trap 'rm -f "$tmp"' EXIT

jq --arg tag "$TAG" --arg version "$VERSION" '
  .plugins |= map(
    if .name == "dev-loop" and .source.ref
    then .source.ref = $tag | .version = $version
    else . end
  )
' "$MARKETPLACE" > "$tmp"

mv "$tmp" "$MARKETPLACE"
trap - EXIT

echo "updated: dev-loop $current_ref -> $TAG (version $current_version -> $VERSION)"
exit 3
