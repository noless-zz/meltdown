#!/usr/bin/env bash
# Starts the exported dedicated server headless for a few seconds and fails
# if it exits with an error (MP-3). Run `tools/build.sh server` first.
# Usage: tools/smoke_server.sh [seconds]
set -uo pipefail

seconds="${1:-5}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server="$root/build/meltdown-server.x86_64"
log="$root/build/server-smoke.log"

if [ ! -x "$server" ]; then
	echo "Missing $server; run tools/build.sh server first" >&2
	exit 2
fi

timeout "$seconds" "$server" --headless > "$log" 2>&1
status=$?
cat "$log"

# 124 means the server was still running when the time was up, which is the
# healthy case for a process that is meant to stay up.
if [ "$status" -ne 124 ] && [ "$status" -ne 0 ]; then
	echo "Server exited with status $status" >&2
	exit 1
fi
# Godot keeps running, and exits 0, after a script error. The log also holds
# harmless engine errors about the missing OpenXR runtime, so only script
# errors are matched.
if grep -q "SCRIPT ERROR" "$log"; then
	echo "Server logged a script error" >&2
	exit 1
fi
echo "Server smoke test passed (status $status after ${seconds}s)"
