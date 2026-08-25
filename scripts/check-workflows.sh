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
#   5. it grants `contents: write` only if it is on the allowlist below
#
# Why (5): main is protected by a ruleset whose only bypass actor is the GitHub
# Actions app, so ANY workflow holding contents write can commit straight to
# main. Pinning that set here means a new write-capable workflow cannot appear
# without an edit to this allowlist, in the same PR, where it is reviewable.
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

# Workflows allowed to hold `contents: write`, and why each one needs it.
#   auto-tag.yml          pushes the vX.Y.Z tag on a version bump
#   release.yml           creates the GitHub Release for that tag
#   sync-dev-loop-pin.yml commits the dev-loop pin bump to main
WRITE_ALLOWLIST="auto-tag.yml release.yml sync-dev-loop-pin.yml"

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
    grants_write = lambda do |perms|
      case perms
      when String then perms == "write-all"
      when Hash   then perms["contents"].to_s == "write"
      else false
      end
    end
    writes = grants_write.call(doc["permissions"])
    (doc["jobs"] || {}).each_value do |job|
      writes ||= grants_write.call(job["permissions"]) if job.is_a?(Hash)
    end
    File.write(File.join(ARGV[1], "GRANTS_CONTENTS_WRITE"), "1") if writes
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

  if [ -f "$SCRATCH/$(basename "$wf").d/GRANTS_CONTENTS_WRITE" ]; then
    case " $WRITE_ALLOWLIST " in
      *" $(basename "$wf") "*) : ;;
      *)
        echo "check-workflows: $(basename "$wf"): grants 'contents: write' but is not on WRITE_ALLOWLIST." >&2
        echo "  Any workflow with contents write can commit straight to main (the branch" >&2
        echo "  ruleset bypasses the GitHub Actions app). Add it to the allowlist in this" >&2
        echo "  script, with the reason, if that is intended." >&2
        status=1
        ;;
    esac
  fi

  [ "$status" -eq 0 ] && echo "ok: $(basename "$wf")"
done

if [ "$found" -eq 0 ]; then
  echo "check-workflows: no workflow files in $WORKFLOW_DIR" >&2
  exit 2
fi

exit "$status"
