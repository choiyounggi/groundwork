#!/usr/bin/env bash
# groundwork — release notes for ONE plugin's tag. Lists the commits that
# touched that plugin's directory since the plugin's own previous tag.
#
# Why not `gh release create --generate-notes`: every plugin here shares one
# `v*` tag namespace, so GitHub compares a new tag against the previous
# release of WHICHEVER plugin was released last, and lists every PR in that
# range. file-lifecycle 0.1.1 got six dev-loop pin bumps and a compare link
# of v0.3.2...v0.1.1 (session-progress's tag).
#
# The plugin's previous tag is the newest `v*` tag merged into <tag> whose
# <plugin-dir>/.claude-plugin/plugin.json version equals the tag — the same
# tag-to-plugin rule auto-tag.sh uses for its collision check.
#
# Usage: release-notes.sh <tag> <plugin-dir> [repo-root]
#   <plugin-dir> is relative to the repo root, e.g. plugins/file-lifecycle
#   $GITHUB_REPOSITORY (owner/repo), when set, adds a "Full Changelog" link.
#
# Output: Markdown on stdout.
#
# Exit codes:
#   0  notes printed
#   2  usage error, <tag> does not exist, or <plugin-dir> is not a plugin at <tag>
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "usage: release-notes.sh <tag> <plugin-dir> [repo-root]" >&2
  exit 2
fi

TAG="$1"
PLUGIN_DIR="${2#./}"
PLUGIN_DIR="${PLUGIN_DIR%/}"
REPO_ROOT="${3:-.}"

if ! git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "release-notes: tag not found: $TAG" >&2
  exit 2
fi

if ! git -C "$REPO_ROOT" cat-file -e "$TAG:$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null; then
  echo "release-notes: no $PLUGIN_DIR/.claude-plugin/plugin.json at $TAG" >&2
  exit 2
fi

prev=""
while IFS= read -r t; do
  [ "$t" = "$TAG" ] && continue
  v=$(git -C "$REPO_ROOT" show "$t:$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null | jq -r ".version" 2>/dev/null || echo "")
  if [ "v$v" = "$t" ]; then
    prev="$t"
    break
  fi
done < <(git -C "$REPO_ROOT" tag --list 'v*' --merged "$TAG" --sort=-v:refname)

if [ -n "$prev" ]; then
  range="$prev..$TAG"
else
  range="$TAG"
fi

echo "## What's Changed"
git -C "$REPO_ROOT" log --format='* %s' "$range" -- "$PLUGIN_DIR"

if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  echo
  if [ -n "$prev" ]; then
    echo "**Full Changelog**: https://github.com/$GITHUB_REPOSITORY/compare/$prev...$TAG"
  else
    echo "**Full Changelog**: https://github.com/$GITHUB_REPOSITORY/commits/$TAG/$PLUGIN_DIR"
  fi
fi
