#!/usr/bin/env bash
# Generates and validates N mine levels (seeds 1..N), each with the generator's
# reactor, and prints one summary line (#317, #357, GEN-3) that ends with how
# many seeds failed each check, the reactor and escape-time checks included. The QA plan asks for 1,000 seeds per pull request (run by
# the unit tests) and 10,000 nightly; .github/workflows/nightly-seeds.yml calls
# this with --all-failures 10000 (#358).
#
# Usage: tools/validate_seeds.sh [--all-failures] [seeds] [first-seed]
# Failure messages go to stderr: the first ten, or every one with --all-failures.
# Needs `godot` on PATH and an imported project (godot --headless --path game --import).
set -euo pipefail

keep=()
if [[ "${1:-}" == "--all-failures" ]]; then
	keep=(--keep=0)
	shift
fi
seeds="${1:-1000}"
first="${2:-1}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec godot --headless --path "$root/game" -s res://tests/validate_seeds.gd -- \
	--seeds="$seeds" --first="$first" "${keep[@]}"
