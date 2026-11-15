#!/usr/bin/env bash
# Checks tools/release_notes.sh against fixed times, one in winter and one in
# Israeli summer time, so a broken time-zone conversion fails CI (DEV-8).
# Usage: tools/test_release_notes.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release_notes.sh"
sha="0123456789abcdef0123456789abcdef01234567"
failures=0

expect_line() {
	local name="$1" output="$2" line="$3"
	if grep -qxF -- "$line" <<< "$output"; then
		echo "ok   $name"
	else
		echo "FAIL $name: expected the line '$line' in:" >&2
		echo "$output" >&2
		failures=$((failures + 1))
	fi
}

expect_text() {
	local name="$1" output="$2" text="$3"
	if grep -qF -- "$text" <<< "$output"; then
		echo "ok   $name"
	else
		echo "FAIL $name: expected '$text' in:" >&2
		echo "$output" >&2
		failures=$((failures + 1))
	fi
}

expect_refused() {
	local name="$1"
	shift
	if "$script" "$@" > /dev/null 2>&1; then
		echo "FAIL $name: the script accepted '$*'" >&2
		failures=$((failures + 1))
	else
		echo "ok   $name"
	fi
}

# 2026-01-15 10:00 UTC: Israel Standard Time, UTC+2.
winter="$("$script" "$sha" 1768471200)"
expect_line "winter time" "$winter" "Built: 2026-01-15 10:00 UTC (2026-01-15 12:00 Asia/Jerusalem)"
expect_text "winter text names the commit" "$winter" "commit ${sha}"
expect_text "default text lists every build" "$winter" "Quest APK"

# 2026-07-15 10:00 UTC: Israel Daylight Time, UTC+3.
summer="$("$script" "$sha" 1784109600 server)"
expect_line "summer time" "$summer" "Built: 2026-07-15 10:00 UTC (2026-07-15 13:00 Asia/Jerusalem)"
expect_text "summer text names the commit" "$summer" "commit ${sha}"
expect_text "server text names the server" "$summer" "dedicated server build"

expect_refused "missing time" "$sha"
expect_refused "time that is not a number" "$sha" "yesterday"
expect_refused "unknown kind" "$sha" 1768471200 apk

if [ "$failures" -gt 0 ]; then
	echo "$failures release notes check(s) failed" >&2
	exit 1
fi
echo "All release notes checks passed"
