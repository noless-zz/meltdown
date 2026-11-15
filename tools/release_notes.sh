#!/usr/bin/env bash
# Prints the body of the rolling `main-latest` release (DEV-8). The release
# page only shows when the release was first created, which made a fresh
# build look stale, so the body states when this build was made: in UTC and
# in Asia/Jerusalem, where the owner is. The system time-zone data handles
# summer time.
# Usage: tools/release_notes.sh <commit-sha> <unix-time> [server|all]
#   server  the text for the server-only publish step
#   all     the text once every build is uploaded (default)
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "Usage: $0 <commit-sha> <unix-time> [server|all]" >&2
	exit 2
fi

sha="$1"
built_at="$2"
kind="${3:-all}"

if ! [[ "$built_at" =~ ^[0-9]+$ ]]; then
	echo "The build time must be a Unix time in seconds, got '$built_at'" >&2
	exit 2
fi

case "$kind" in
	server)
		echo "Latest dedicated server build from main, commit ${sha}. Replaced on every push; not a versioned release."
		;;
	all)
		echo "Latest Quest APK (debug), desktop client and dedicated server from main, commit ${sha}. Replaced on every push; not a versioned release."
		;;
	*)
		echo "Unknown kind '$kind': use server or all" >&2
		exit 2
		;;
esac

utc="$(TZ=UTC date -d "@${built_at}" '+%Y-%m-%d %H:%M')"
local_time="$(TZ=Asia/Jerusalem date -d "@${built_at}" '+%Y-%m-%d %H:%M')"
echo
echo "Built: ${utc} UTC (${local_time} Asia/Jerusalem)"
