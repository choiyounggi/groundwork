#!/usr/bin/env bash
# groundwork — verify every GitHub Actions workflow actually registers.
#
# A workflow whose YAML does not parse is NOT an error you see: GitHub keeps it
# "active", lists it by filename instead of by `name`, and gives it NO triggers.
# It simply never runs. That happened to sync-dev-loop-pin.yml — a continuation
# line at column 0 inside a `run: |` block ended the block scalar, so the file
# was unparseable and the hourly schedule silently never fired.
#
# Checks per workflow file:
#   1. the YAML parses
#   2. it has a top-level `name`
#   3. it has at least one trigger (`on:`)
#   4. every `run:` script is valid bash (bash -n)
#
# Usage: check-workflows.sh [repo-root]   (repo-root defaults to ".")
#
# Exit codes:
#   0  every workflow parses and every run block is valid bash
#   1  at least one workflow is broken (details on stderr)
#   2  usage error, no workflow directory, or ruby unavailable to parse YAML
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: check-workflows.sh [repo-root]" >&2
  exit 2
fi

REPO_ROOT="${1:-.}"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

if [ ! -d "$WORKFLOW_DIR" ]; then
  echo "check-workflows: no workflow directory: $WORKFLOW_DIR" >&2
  exit 2
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "check-workflows: ruby is required to parse workflow YAML" >&2
  exit 2
fi

# Scratch dir for the extracted run scripts — inside the repo's own tmp, never
# /tmp, and removed on exit.
SCRATCH="$(mktemp -d "${TMPDIR:-$REPO_ROOT}/check-workflows.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

status=0
found=0

for wf in "$WORKFLOW_DIR"/*.yml "$WORKFLOW_DIR"/*.yaml; do
  [ -f "$wf" ] || continue
  found=$((found + 1))

  # Ruby parses YAML 1.1, where the unquoted key `on` reads as boolean true —
  # the same normalization GitHub applies, so check both spellings.
  if ! ruby -ryaml -e '
    doc = YAML.load_file(ARGV[0])
    abort "not a mapping" unless doc.is_a?(Hash)
    abort "no top-level name" if doc["name"].to_s.strip.empty?
    triggers = doc.key?(true) ? doc[true] : doc["on"]
    abort "no triggers (on:)" if triggers.nil? || (triggers.respond_to?(:empty?) && triggers.empty?)
    Dir.mkdir(ARGV[1]) unless Dir.exist?(ARGV[1])
    (doc["jobs"] || {}).each do |job_name, job|
      (job["steps"] || []).each_with_index do |step, i|
        next unless step.is_a?(Hash) && step["run"]
        File.write(File.join(ARGV[1], "#{job_name}-#{i}.sh"), step["run"])
      end
    end
  ' "$wf" "$SCRATCH/$(basename "$wf").d" 2>"$SCRATCH/err"; then
    echo "check-workflows: $(basename "$wf"): $(cat "$SCRATCH/err")" >&2
    status=1
    continue
  fi

  for script in "$SCRATCH/$(basename "$wf").d"/*.sh; do
    [ -f "$script" ] || continue
    if ! bash -n "$script" 2>"$SCRATCH/err"; then
      echo "check-workflows: $(basename "$wf"): run block $(basename "$script" .sh) is not valid bash: $(cat "$SCRATCH/err")" >&2
      status=1
    fi
  done

  [ "$status" -eq 0 ] && echo "ok: $(basename "$wf")"
done

if [ "$found" -eq 0 ]; then
  echo "check-workflows: no workflow files in $WORKFLOW_DIR" >&2
  exit 2
fi

exit "$status"
