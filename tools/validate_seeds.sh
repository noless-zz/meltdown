#!/usr/bin/env bash
# Generates and validates N mine levels (seeds 1..N) and prints one summary
# line (#317, GEN-3). The QA plan asks for 1,000 seeds per pull request (run by
# the unit tests) and 10,000 nightly; a nightly job calls this with 10000.
#
# Usage: tools/validate_seeds.sh [seeds] [first-seed]
# Needs `godot` on PATH and an imported project (godot --headless --path game --import).
set -euo pipefail

seeds="${1:-1000}"
first="${2:-1}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec godot --headless --path "$root/game" -s res://tests/validate_seeds.gd -- \
	--seeds="$seeds" --first="$first"
