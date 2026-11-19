#!/usr/bin/env bash
# Checks tools/update_quest.sh against stub `curl` and `adb` commands, a
# made-up APK and a trimmed copy of the real main-latest release, so no network or headset is
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

# The APK is made here, not committed: `*.apk` is git-ignored.
make_release() {
	echo "Not a real APK: a fixture for tools/test_update_quest.sh." > "$1/meltdown-quest-debug.apk"
	(cd "$1" && sha256sum meltdown-quest-debug.apk > meltdown-quest-debug.apk.sha256)
}

# Runs the script in a fresh scenario. Sets $output, $status, $log (the adb
# calls, one per line) and $tmp (the script's temporary folder).
run_scenario() {
	local devices="$1"
	shift
	local dir="$work/scenario$RANDOM$RANDOM"
	mkdir -p "$dir/release" "$dir/state" "$dir/tmp"
	tmp="$dir/tmp"
	make_release "$dir/release"
	cp "$fixtures/release.json" "$dir/release/"
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
		STUB_ADB_BLANK="${BLANK:-}" \
		STUB_ADB_SEQUENCE="${SEQUENCE:-}" \
		STUB_ADB_WAIT="${WAIT:-}" \
		MELTDOWN_DEVICE_WAIT_SECONDS=1 \
		TMPDIR="$tmp" \
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
if [ "$(count_lines "no-streaming")" -eq 0 ]; then
	pass "a failure with a reason is not retried"
else
	fail "a failure with a reason is not retried"
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

# The uninstall does not help: the reason is printed, and still not retried.
INCOMPATIBLE=sticky run_scenario "$one" --uninstall-first
if [ "$status" -ne 0 ] \
	&& [ "$(count_lines " install -r ")" -eq 2 ] \
	&& [ "$(count_lines "no-streaming")" -eq 0 ] \
	&& grep -q "^  Reason: Failure \[INSTALL_FAILED_UPDATE_INCOMPATIBLE" <<< "$output" \
	&& grep -q "^  To try by hand: adb -s QUEST3A install -r " <<< "$output" \
	&& ! grep -q "adb gave no reason" <<< "$output"; then
	pass "a failure with a reason prints it and the manual command"
else
	fail "a failure with a reason prints it and the manual command (status $status)"
fi

# #210: adb fails with a blank reason on every attempt. Since #589 it is
# retried twice, not once.
BLANK=always run_scenario "$one"
kept="$(find "$tmp" -name meltdown-quest-debug.apk)"
if [ "$status" -ne 0 ] \
	&& [ "$(count_lines "^-s QUEST3A install -r /")" -eq 1 ] \
	&& [ "$(count_lines "^-s QUEST3A install -r --no-streaming /")" -eq 2 ] \
	&& grep -qxF "  adb gave no reason." <<< "$output" \
	&& ! grep -qxF "  Installed." <<< "$output"; then
	pass "a blank failure is retried twice without streaming, then says adb gave no reason"
else
	fail "a blank failure is retried twice without streaming, then says adb gave no reason (status $status)"
fi
if [ -n "$kept" ] && grep -qxF "  To try by hand: adb -s QUEST3A install -r \"$kept\"" <<< "$output"; then
	pass "a failed install prints the manual command and keeps the APK it names"
else
	fail "a failed install prints the manual command and keeps the APK it names"
fi

# #210: the streamed install fails blank, the unstreamed one works.
BLANK=streamed run_scenario "$one"
if [ "$status" -eq 0 ] \
	&& [ "$(count_lines " install -r ")" -eq 2 ] \
	&& [ "$(count_lines "install -r --no-streaming")" -eq 1 ] \
	&& grep -qxF "  Installed." <<< "$output" \
	&& ! grep -q "Install failed" <<< "$output" \
	&& [ -z "$(ls -A "$tmp")" ]; then
	pass "a blank streamed failure that works without streaming reports Installed."
else
	fail "a blank streamed failure that works without streaming reports Installed. (status $status)"
fi

# #589: the connection is woken before the first install: wait, wake, install.
run_scenario "$one"
order="$(grep -E "^-s QUEST3A (wait-for-device|shell true|install)" <<< "$log" | cut -d' ' -f3- | cut -d' ' -f1-2)"
if [ "$status" -eq 0 ] && [ "$order" = $'wait-for-device\nshell true\ninstall -r' ]; then
	pass "waits for the headset and wakes it before the first install"
else
	fail "waits for the headset and wakes it before the first install (order: ${order//$'\n'/, })"
fi

# #589: blank, then `not found`, then success, as on the owner's headset.
SEQUENCE="blank notfound ok" run_scenario "$one"
order="$(grep -E "^-s QUEST3A (wait-for-device|install)" <<< "$log" | cut -d' ' -f3)"
if [ "$status" -eq 0 ] \
	&& [ "$(count_lines " install -r ")" -eq 3 ] \
	&& [ "$order" = $'wait-for-device\ninstall\nwait-for-device\ninstall\nwait-for-device\ninstall' ] \
	&& grep -qxF "  Installed." <<< "$output" \
	&& ! grep -q "Install failed" <<< "$output"; then
	pass "a headset that drops off and comes back is waited for and installed"
else
	fail "a headset that drops off and comes back is waited for and installed (status $status)"
fi

# #589: the headset stays `not found`: the plain reason, the manual command
# and the kept download; never more than two retries.
for gone in notfound offline; do
	SEQUENCE="$gone" run_scenario "$one"
	kept="$(find "$tmp" -name meltdown-quest-debug.apk)"
	if [ "$status" -ne 0 ] \
		&& [ "$(count_lines " install -r ")" -eq 3 ] \
		&& grep -q "the headset dropped off USB for a moment" <<< "$output" \
		&& ! grep -q "adb gave no reason" <<< "$output" \
		&& [ -n "$kept" ] \
		&& grep -qxF "  To try by hand: adb -s QUEST3A install -r \"$kept\"" <<< "$output"; then
		pass "a headset that stays $gone gets the plain reason and the manual command"
	else
		fail "a headset that stays $gone gets the plain reason and the manual command (status $status)"
	fi
done

# #589: the wait is bounded; a headset that never comes back does not hang.
started="$(date +%s)"
SEQUENCE="notfound" WAIT=hang run_scenario "$one"
took=$(($(date +%s) - started))
if [ "$status" -ne 0 ] && [ "$took" -lt 10 ] \
	&& [ "$(count_lines " install -r ")" -eq 1 ] \
	&& grep -q "did not come back within 1 s" <<< "$output" \
	&& grep -q "the headset dropped off USB for a moment" <<< "$output"; then
	pass "the wait for the headset gives up after the named time"
else
	fail "the wait for the headset gives up after the named time (status $status, ${took} s)"
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
make_release "$dir/release"
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
