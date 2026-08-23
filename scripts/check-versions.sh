#!/usr/bin/env bash
# groundwork — CI-enforced version consistency between marketplace.json and
# each local plugin's plugin.json.
#
# Usage: check-versions.sh [repo-root]   (repo-root defaults to ".")
#
# Exit codes:
#   0  every local-source plugin's version matches its plugin.json
#      (url/object-source entries are skipped, not compared)
#   1  at least one version mismatch
#   2  usage error, missing/unparseable marketplace.json, a missing/non-array/
#      empty .plugins, or a local-source plugin with no plugin.json at its
#      expected path
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: check-versions.sh [repo-root]" >&2
  exit 2
fi

REPO_ROOT="${1:-.}"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"

if [ ! -f "$MARKETPLACE" ]; then
  echo "check-versions: marketplace file not found: $MARKETPLACE" >&2
  exit 2
fi

if ! jq empty "$MARKETPLACE" >/dev/null 2>&1; then
  echo "check-versions: unparseable JSON: $MARKETPLACE" >&2
  exit 2
fi

plugins_type=$(jq -r '.plugins | type' "$MARKETPLACE")
count=$(jq '.plugins | length' "$MARKETPLACE")

if [ "$plugins_type" != "array" ] || [ "$count" -eq 0 ]; then
  echo "check-versions: no .plugins array found (or it is empty) in $MARKETPLACE" >&2
  exit 2
fi

status=0
i=0
while [ "$i" -lt "$count" ]; do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source_type=$(jq -r ".plugins[$i].source | type" "$MARKETPLACE")

  if [ "$source_type" != "string" ]; then
    echo "skip: $name (non-local source, no plugin.json to compare)"
    i=$((i + 1))
    continue
  fi

  source_path=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
  mkt_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")
  plugin_json="$REPO_ROOT/$source_path/.claude-plugin/plugin.json"

  if [ ! -f "$plugin_json" ]; then
    echo "check-versions: missing plugin.json for $name: $plugin_json" >&2
    exit 2
  fi

  plugin_version=$(jq -r ".version" "$plugin_json")

  if [ "$mkt_version" = "$plugin_version" ]; then
    echo "ok: $name $mkt_version"
  else
    echo "check-versions: version mismatch for $name: marketplace=$mkt_version plugin.json=$plugin_version — sync the two" >&2
    status=1
  fi

  i=$((i + 1))
done

exit "$status"
