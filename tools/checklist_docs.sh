#!/usr/bin/env bash
# Writes docs/checklists/<id>.md from every in-game checklist file under
# game/data/checklists/ (#1325), so the headset and the docs show one text.
# Run it after editing a checklist file; the unit tests fail until you do.
#
# Usage: tools/checklist_docs.sh
# Needs `godot` on PATH and an imported project (godot --headless --path game --import).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec godot --headless --path "$root/game" -s res://tests/checklist_docs.gd
