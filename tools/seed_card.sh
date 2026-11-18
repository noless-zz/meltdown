#!/usr/bin/env bash
# Prints one MELTDOWN_SEED_CARD line per generated seed: modules, loops, robots,
# debris spheres, blast doors, fires, the escape from the reactor and its
# countdown (#532, DEV-6). With --pick=3 it instead prints three seeds that
# between them have a loop, a door, a fire and the range's longest escape,
# preferring seeds the m3 suite does not fly, for the G3 headset session.
# Adding --fair makes the pick take only seeds the bot pilot clears and escapes (#547).
#
# Usage: tools/seed_card.sh [--seeds=N] [--first=S] [--pick=N [--fair]]
# Defaults: --seeds=200 --first=1. Every argument is passed through.
# Needs `godot` on PATH and an imported project (godot --headless --path game --import).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec godot --headless --path "$root/game" -s res://tests/seed_card.gd -- "$@"
