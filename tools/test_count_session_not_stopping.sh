#!/usr/bin/env bash
# Checks tools/count_session_not_stopping.sh against sample logs with 0, 1 and
# 2 matching lines (issue #575). Needs no Godot or Monado.
# Usage: tools/test_count_session_not_stopping.sh
set -euo pipefail

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$tools/count_session_not_stopping.sh"
failures=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Lines shaped like Godot 4.7's OpenXR errors against Monado, plus unrelated
# lines that must not count.
cat > "$work/zero.log" <<'LOG'
OpenXR: Running on OpenXR runtime:  Monado(XRT) by Collabora et al
MELTDOWN_XR_SMOKE {"session":true,"views":2,"left_tracked":true,"right_tracked":true}
ERROR: OpenXR: failed to get action state [ XR_ERROR_SESSION_NOT_RUNNING ]
LOG
cat > "$work/one.log" <<'LOG'
MELTDOWN_XR_SMOKE {"session":true,"views":2,"left_tracked":true,"right_tracked":true}
ERROR: OpenXR: Failed to destroy session [ XR_ERROR_SESSION_NOT_STOPPING ]
   at: _destroy_session (modules/openxr/openxr_api.cpp:1000)
LOG
cat > "$work/two.log" <<'LOG'
MELTDOWN_XR_SMOKE {"session":true,"views":2,"left_tracked":true,"right_tracked":true}
ERROR: OpenXR: Failed to end session [ XR_ERROR_SESSION_NOT_STOPPING ]
ERROR: OpenXR: failed to get action state [ XR_ERROR_SESSION_NOT_RUNNING ]
ERROR: OpenXR: Failed to destroy session [ XR_ERROR_SESSION_NOT_STOPPING ]
LOG

check() {
	local name="$1" expected="$2" actual
	actual="$("$script" "$work/$name.log")"
	if [ "$actual" = "$expected" ]; then
		echo "ok   $name.log counts $expected"
	else
		echo "FAIL $name.log: expected $expected, got '$actual'" >&2
		failures=$((failures + 1))
	fi
}

check zero 0
check one 1
check two 2

if "$script" "$work/missing.log" > /dev/null 2>&1; then
	echo "FAIL a missing log should be an error" >&2
	failures=$((failures + 1))
else
	echo "ok   a missing log is an error"
fi

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "all checks passed"
