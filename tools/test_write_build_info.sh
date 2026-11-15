#!/usr/bin/env bash
# Checks tools/write_build_info.sh (DEV-8). A valid call must write exactly the
# committed fixture game/tests/fixtures/build_info_valid.tres, which the unit
# tests load through BuildInfo, so together they show the written file can be
# read. Bad input must exit non-zero and write nothing.
# Usage: tools/test_write_build_info.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/tools/write_build_info.sh"
fixture="$root/game/tests/fixtures/build_info_valid.tres"
sha="0123456789abcdef0123456789abcdef01234567"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failures=0

fail() {
	echo "FAIL $1" >&2
	failures=$((failures + 1))
}

out="$scratch/valid.tres"
if "$script" "$sha" 1768471200 "$out" && cmp -s "$fixture" "$out"; then
	echo "ok   valid call writes the fixture BuildInfo reads"
else
	fail "valid call: output differs from $fixture"
	[ -f "$out" ] && cat "$out" >&2
fi

out="$scratch/upper.tres"
if "$script" "${sha^^}" 01768471200 "$out" && cmp -s "$fixture" "$out"; then
	echo "ok   upper-case commit and leading zero are normalised"
else
	fail "upper-case commit or leading zero: output differs from $fixture"
fi

expect_refused() {
	local name="$1"
	shift
	local out="$scratch/refused.tres"
	rm -f "$out"
	if "$script" "$@" "$out" > /dev/null 2>&1; then
		fail "$name: the script accepted '$*'"
	elif [ -e "$out" ] || compgen -G "$out.*" > /dev/null; then
		fail "$name: a file was written"
	else
		echo "ok   $name"
	fi
}

expect_refused "short commit" "${sha:0:39}" 1768471200
expect_refused "long commit" "${sha}0" 1768471200
expect_refused "commit that is not hex" "g${sha:1}" 1768471200
expect_refused "time that is not a number" "$sha" yesterday
expect_refused "negative time" "$sha" -5
expect_refused "fractional time" "$sha" 1768471200.5
expect_refused "empty time" "$sha" ""

if "$script" "$sha" 1768471200 > /dev/null 2>&1; then
	fail "missing output: the script accepted two arguments"
else
	echo "ok   missing output"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures build info check(s) failed" >&2
	exit 1
fi
echo "All build info checks passed"
