#!/usr/bin/env bash
# Paced demo for asciinema. Runs the guardrails self-test with small pauses so the
# decisions land line by line. Nothing dangerous is executed — the self-test only
# feeds command strings through the guard as hook data.
#
# Usage: asciinema rec -c "bash docs/demo/record-demo.sh" groundwork-demo.cast
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ST="$ROOT/plugins/guardrails/scripts/self-test.sh"

type_line() { printf '%s\n' "$1"; sleep "${2:-0.6}"; }

clear 2>/dev/null || true
type_line ""
type_line "  \$ # groundwork/guardrails — is my Claude Code agent actually protected?" 0.8
type_line "  \$ /guardrails:self-test" 1.0
sleep 0.4
bash "$ST"
sleep 1.2
type_line "  \$ # every dangerous command was caught — and none of them ran." 1.2
sleep 0.6
