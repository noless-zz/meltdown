#!/usr/bin/env bash
# Fails if the clone holds files that are neither committed nor ignored, or
# committed files that changed (ARC-5). CI runs it straight after
# `godot --headless --path game --import`: an import that writes something
# new, such as the `.uid` file of a script committed without one, would
# otherwise give every clone its own copy with different identifiers.
# Usage: tools/check_clean_import.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --untracked-files=all lists each file instead of only its new folder.
stray="$(git -C "$root" status --porcelain --untracked-files=all)"

if [ -n "$stray" ]; then
	echo "The clone is not clean. Commit these files or add them to .gitignore:" >&2
	echo "$stray" >&2
	exit 1
fi
echo "The clone is clean"
