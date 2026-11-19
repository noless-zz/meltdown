#!/usr/bin/env bash
# Prints how many lines of a game log contain XR_ERROR_SESSION_NOT_STOPPING
# (issue #575). Godot logs it when the game quits without first ending the
# OpenXR session (#558); counting it lets CI show when a fix removes it.
# Usage: tools/count_session_not_stopping.sh <log file>
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
	echo "usage: $0 <log file>" >&2
	exit 2
fi
# grep -c exits 1 when nothing matches; zero matches is a valid count.
grep -a -c 'XR_ERROR_SESSION_NOT_STOPPING' "$1" || true
