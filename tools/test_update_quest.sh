#!/usr/bin/env bash
# Checks tools/update_quest.sh against stub `curl` and `adb` commands and a
# trimmed copy of the real main-latest release, so no network or headset is
# needed (playtest #104, DEV-8).
# Usage: tools/test_update_quest.sh
set -euo pipefail

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$tools/update_quest.sh"
fixtures="$tools/fixtures/update_quest"
release_commit="388a31ab920b9254da445bf154c4e99350d5f3f6"
failures=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass() {
	echo "ok   $1"
}

fail() {
	echo "FAIL $1" >&2
	echo "$output" >&2
	failures=$((failures + 1))
}

# Runs the script in a fresh scenario. Sets $output, $status and $log (the adb
# calls, one per line).
run_scenario() {
	local devices="$1"
	shift
	local dir="$work/scenario$RANDOM$RANDOM"
	mkdir -p "$dir/release" "$dir/state"
	cp "$fixtures/meltdown-quest-debug.apk" "$fixtures/meltdown-quest-debug.apk.sha256" \
		"$fixtures/release.json" "$dir/release/"
	if [ "${BAD_CHECKSUM:-0}" = "1" ]; then
		echo "0000000000000000000000000000000000000000000000000000000000000000  meltdown-quest-debug.apk" \
			> "$dir/release/meltdown-quest-debug.apk.sha256"
	fi
	: > "$dir/adb.log"
	status=0
	output="$(PATH="$fixtures/bin:$PATH" \
		STUB_RELEASE_DIR="$dir/release" \
		STUB_ADB_LOG="$dir/adb.log" \
		STUB_ADB_STATE="$dir/state" \
		STUB_ADB_DEVICES="$devices" \
		STUB_ADB_INCOMPATIBLE="${INCOMPATIBLE:-0}" \
		"$script" "$@" 2>&1)" || status=$?
	log="$(cat "$dir/adb.log")"
}

count_lines() {
	grep -c -- "$1" <<< "$log" || true
}

one="QUEST3A\tdevice\n"
two="QUEST3A\tdevice\n192.168.1.20:5555\tdevice\nOFFLINE1\toffline\n"

# A good release on one headset.
run_scenario "$one"
if [ "$status" -eq 0 ] && [ "$(count_lines " install -r ")" -eq 1 ]; then
	pass "one headset gets one install"
else
	fail "one headset gets one install (status $status)"
fi
if grep -qxF "Build: commit $release_commit" <<< "$output" \
	&& grep -qxF "Built: 2026-11-15 17:06 UTC (2026-11-15 19:06 Asia/Jerusalem)" <<< "$output"; then
	pass "prints the commit and build time from the release"
else
	fail "prints the commit and build time from the release"
fi
if [ "$(count_lines "monkey")" -eq 0 ]; then
	pass "does not start the game without --launch"
else
	fail "does not start the game without --launch"
fi

# A checksum mismatch never reaches adb install.
BAD_CHECKSUM=1 run_scenario "$one"
if [ "$status" -ne 0 ] && [ "$(count_lines "install")" -eq 0 ] && grep -q "Checksum mismatch" <<< "$output"; then
	pass "checksum mismatch installs nothing"
else
	fail "checksum mismatch installs nothing (status $status)"
fi

# Two ready headsets (USB and Wi-Fi) and one offline: two installs.
run_scenario "$two" --launch
if [ "$status" -eq 0 ] \
	&& [ "$(count_lines "^-s QUEST3A install -r ")" -eq 1 ] \
	&& [ "$(count_lines "^-s 192.168.1.20:5555 install -r ")" -eq 1 ] \
	&& [ "$(count_lines "OFFLINE1")" -eq 0 ]; then
	pass "two headsets get two installs, the offline one none"
else
	fail "two headsets get two installs, the offline one none (status $status)"
fi
if [ "$(count_lines "shell monkey -p io.github.nolesszz.meltdown")" -eq 2 ]; then
	pass "--launch starts the game on each headset"
else
	fail "--launch starts the game on each headset"
fi

# A copy signed with another key: explain, and uninstall only when asked.
INCOMPATIBLE=1 run_scenario "$one"
if [ "$status" -ne 0 ] && [ "$(count_lines "uninstall")" -eq 0 ] \
	&& grep -q "different signature" <<< "$output" \
	&& grep -q -- "--uninstall-first" <<< "$output"; then
	pass "signature mismatch explains and does not uninstall"
else
	fail "signature mismatch explains and does not uninstall (status $status)"
fi

INCOMPATIBLE=1 run_scenario "$one" --uninstall-first
if [ "$status" -eq 0 ] \
	&& [ "$(count_lines "^-s QUEST3A uninstall io.github.nolesszz.meltdown$")" -eq 1 ] \
	&& [ "$(count_lines " install -r ")" -eq 2 ] \
	&& grep -q "saved data is lost" <<< "$output"; then
	pass "--uninstall-first uninstalls and installs again"
else
	fail "--uninstall-first uninstalls and installs again (status $status)"
fi

# No headset at all.
run_scenario ""
if [ "$status" -ne 0 ] && [ "$(count_lines "install")" -eq 0 ] && grep -q "No headset found" <<< "$output"; then
	pass "no headset exits non-zero with a clear message"
else
	fail "no headset exits non-zero with a clear message (status $status)"
fi

run_scenario "OFFLINE1\tunauthorized\n"
if [ "$status" -ne 0 ] && [ "$(count_lines "install")" -eq 0 ]; then
	pass "an unauthorized headset counts as none"
else
	fail "an unauthorized headset counts as none (status $status)"
fi

# The release API is down: the update still goes ahead.
dir="$work/noapi"
mkdir -p "$dir/release" "$dir/state"
cp "$fixtures/meltdown-quest-debug.apk" "$fixtures/meltdown-quest-debug.apk.sha256" "$dir/release/"
: > "$dir/adb.log"
status=0
output="$(PATH="$fixtures/bin:$PATH" STUB_RELEASE_DIR="$dir/release" STUB_ADB_LOG="$dir/adb.log" \
	STUB_ADB_STATE="$dir/state" STUB_ADB_DEVICES="$one" "$script" 2>&1)" || status=$?
if [ "$status" -eq 0 ] && grep -qxF "Build: commit unknown" <<< "$output"; then
	pass "missing release text still installs and says unknown"
else
	fail "missing release text still installs and says unknown (status $status)"
fi

run_scenario "$one" --bogus
if [ "$status" -eq 2 ]; then
	pass "unknown option is refused"
else
	fail "unknown option is refused (status $status)"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures update script check(s) failed" >&2
	exit 1
fi
echo "All update script checks passed"
