#!/usr/bin/env bash
# groundwork — auto-tag release detection. For each local plugin, compares
# its current plugin.json version against the repo's git tags and reports
# one of three states: needs a tag+release, already released (skip), or a
# tag-namespace collision — the tag already exists but belongs to a
# different plugin/version (the v1.3.0 incident: the repo's tag namespace
# is shared across plugins, so a version bump can silently reuse someone
# else's tag). This catches that at bump time instead of tag time.
#
# This script only DETECTS. It never creates or pushes tags, so it is safe
# to run locally and in CI on every push, not just on tag events.
#
# Usage: auto-tag.sh [repo-root]   (repo-root defaults to ".")
#
# Output (stdout):
#   need: <tag> <plugin-name>                     tag does not exist yet
#   skip: <tag> already released for <plugin>      tag exists, versions match
#   skip: <plugin> (non-local source, ...)         non-string source, ignored
#
# Exit codes:
#   0  no collisions (plugins needing a tag are reported as `need:` lines)
#   1  at least one tag-namespace collision (see stderr for details)
#   2  usage error, missing/unparseable marketplace.json, a missing/non-array/
#      empty .plugins, or a local-source plugin with no plugin.json at its
#      expected path
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: auto-tag.sh [repo-root]" >&2
  exit 2
fi

REPO_ROOT="${1:-.}"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

if [ ! -f "$MARKETPLACE" ]; then
  echo "auto-tag: marketplace file not found: $MARKETPLACE" >&2
  exit 2
fi

if ! jq empty "$MARKETPLACE" >/dev/null 2>&1; then
  echo "auto-tag: unparseable JSON: $MARKETPLACE" >&2
  exit 2
fi

plugins_type=$(jq -r '.plugins | type' "$MARKETPLACE")
count=$(jq '.plugins | length' "$MARKETPLACE")

if [ "$plugins_type" != "array" ] || [ "$count" -eq 0 ]; then
  echo "auto-tag: no .plugins array found (or it is empty) in $MARKETPLACE" >&2
  exit 2
fi

status=0
i=0
while [ "$i" -lt "$count" ]; do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source_type=$(jq -r ".plugins[$i].source | type" "$MARKETPLACE")

  if [ "$source_type" != "string" ]; then
    echo "skip: $name (non-local source, no plugin.json to tag)"
    i=$((i + 1))
    continue
  fi

  source_path=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
  plugin_json="$REPO_ROOT/$source_path/.claude-plugin/plugin.json"

  if [ ! -f "$plugin_json" ]; then
    echo "auto-tag: missing plugin.json for $name: $plugin_json" >&2
    exit 2
  fi

  version=$(jq -r ".version" "$plugin_json")
  tag="v$version"
  rel_plugin_json="${source_path#./}/.claude-plugin/plugin.json"

  if ! git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "need: $tag $name"
    i=$((i + 1))
    continue
  fi

  tagged_version=$(git -C "$REPO_ROOT" show "$tag:$rel_plugin_json" 2>/dev/null | jq -r ".version" 2>/dev/null || echo "")

  if [ "$tagged_version" = "$version" ]; then
    echo "skip: $tag already released for $name"
  else
    echo "auto-tag: COLLISION on $tag — $name wants version $version but tag $tag already exists with plugin.json version '${tagged_version:-<unreadable>}' at that path — the tag namespace is shared across plugins; bump to an unused version or investigate the existing tag" >&2
    status=1
  fi

  i=$((i + 1))
done

exit "$status"
