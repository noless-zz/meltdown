#!/usr/bin/env bash
# Checks the device acceptance scripts (#154) against a stub adb and made-up
# game logs, so no headset, network or Windows is needed. Needs pwsh, which
# GitHub's Ubuntu runners have.
# Usage: tools/test_device_acceptance.sh
set -euo pipefail

tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixtures="$tools/fixtures/device_acceptance"
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

# A game log as `adb logcat -v raw` prints it: the runner's lines and one
# report between the markers (acceptance_runner.gd, acceptance_report.gd).
write_log() {
	local result="$1" exit_line="$2" passed="false"
	if [ "$result" = "pass" ]; then
		passed="true"
	fi
	cat <<-LOG
	Godot Engine v4.7.2.stable.official
	Meltdown: acceptance: step basic_flight
	Meltdown: acceptance: step basic_flight $result
	MELTDOWN_ACCEPTANCE_BEGIN
	{
		"build_commit": "2c68c89",
		"device": "Quest 3 (Android)",
		"passed": $passed,
		"steps": [
			{
				"id": "basic_flight",
				"measurements": {
					"expected_hash": 861662111,
					"final_hash": 861662111,
					"ticks": 600
				},
				"message": "final_hash: final hash 861662111",
				"result": "$result"
			},
			{
				"id": "frame_budget",
				"measurements": {
					"p99_ms": 11.4,
					"summary": "90.0 Hz, 2700 frames: p99 11.40 ms"
				},
				"message": "frame_budget: 90.0 Hz, 2700 frames: p99 11.40 ms",
				"result": "pass"
			}
		],
		"suite": "m1"
	}
	MELTDOWN_ACCEPTANCE_END
	LOG
	if [ -n "$exit_line" ]; then
		echo "$exit_line"
	fi
}

# The same game's log while the suite is still running: no report, no exit line.
write_running_log() {
	echo "Godot Engine v4.7.2.stable.official"
	echo "Meltdown: refresh rate 90 Hz"
	echo "Meltdown: acceptance: step basic_flight"
}

# Runs device_acceptance.ps1 in a fresh scenario. Sets $output, $status, $log
# (the adb calls, one per line) and $out (the output folder).
run_headset() {
	local devices="$1" game_log="$2"
	local dir="$work/scenario$RANDOM$RANDOM"
	mkdir -p "$dir/release"
	echo "Not a real APK: a fixture for tools/test_device_acceptance.sh." > "$dir/release/meltdown-quest-debug.apk"
	(cd "$dir/release" && sha256sum meltdown-quest-debug.apk > meltdown-quest-debug.apk.sha256)
	if [ "${BAD_CHECKSUM:-0}" = "1" ]; then
		echo "0000000000000000000000000000000000000000000000000000000000000000  meltdown-quest-debug.apk" \
			> "$dir/release/meltdown-quest-debug.apk.sha256"
	fi
	printf '%s\n' "$game_log" > "$dir/godot.log"
	if [ -n "${EARLY_LOG:-}" ]; then
		printf '%s\n' "$EARLY_LOG" > "$dir/early.log"
	fi
	: > "$dir/adb.log"
	# Its own temp folder, so the APK cache (#1437) starts empty unless the
	# test hands one over in $CACHE_FROM.
	mkdir -p "$dir/tmp"
	if [ -n "${CACHE_FROM:-}" ]; then
		cp -R "$CACHE_FROM/." "$dir/tmp/"
	fi
	tmp="$dir/tmp"
	local extra=()
	read -r -a extra <<< "${EXTRA_ARGS:-}"
	out="$dir/out"
	status=0
	output="$(PATH="$fixtures/bin:$PATH" \
		MELTDOWN_APK_DIR="$dir/release" \
		STUB_ADB_LOG="$dir/adb.log" \
		STUB_ADB_DEVICES="$devices" \
		STUB_GODOT_LOG="$dir/godot.log" \
		STUB_ADB_DEAD="${DEAD:-0}" \
		STUB_ADB_INSTALL_SEQUENCE="${INSTALLS:-ok}" \
		STUB_ADB_WAIT="${WAIT:-}" \
		STUB_ADB_LOCKED="${LOCKED:-}" \
		STUB_ADB_BACKGROUND="${BACKGROUND:-0}" \
		STUB_GODOT_EARLY_LOG="${EARLY_LOG:+$dir/early.log}" \
		STUB_GODOT_EARLY_POLLS="${EARLY_POLLS:-0}" \
		STUB_ADB_RESOLVE_SEQUENCE="${RESOLVES:-ok}" \
		STUB_ADB_RESOLVE_ACTIVITY="${RESOLVED:-}" \
		STUB_ADB_NOT_EXPORTED="${NOT_EXPORTED:-}" \
		STUB_ADB_DROP_AT="${DROP_AT:-}" \
		STUB_ADB_DROP_FOR="${DROP_FOR:-never}" \
		STUB_ADB_HARDWARE="${HARDWARE:-}" \
		STUB_GAME_FILES="${GAME_FILES:-}" \
		ANDROID_SERIAL="${SERIAL_ENV:-}" \
		GITHUB_EVENT_NAME="${EVENT:-}" \
		GITHUB_STEP_SUMMARY="$dir/summary.md" \
		STUB_ADB_INSTALLED_SHA="${HEADSET_SHA:-}" \
		STUB_ADB_PM="${PM:-}" \
		MELTDOWN_FORCE_INSTALL="${FORCE_ENV:-}" \
		TMPDIR="$dir/tmp" \
		pwsh -NoProfile -NonInteractive -File "$tools/device_acceptance.ps1" \
		-Suite m1 -OutDir "$out" -PollSeconds 0 -StartGraceSeconds 0 -TimeoutSeconds "${TIMEOUT:-3}" \
		-WakeSeconds 0 -ForegroundGraceSeconds 0 -ResolveRetrySeconds 0 -DeviceWaitSeconds "${DEVICE_WAIT:-5}" \
		-ReconnectSeconds "${RECONNECT:-5}" -ReconnectPollSeconds 0 ${extra[@]+"${extra[@]}"} 2>&1)" || status=$?
	log="$(cat "$dir/adb.log")"
}

status_of() {
	pwsh -NoProfile -NonInteractive -Command "(Get-Content -Raw '$1/result.json' | ConvertFrom-Json).status"
}

# No headset: a clean skip that says why.
run_headset "" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -q "No headset is connected" <<< "$output" \
	&& [ "$(status_of "$out")" = "skipped" ] && ! grep -q "install" <<< "$log"; then
	pass "no headset: skipped with exit 0 and nothing installed"
else
	fail "no headset: skipped with exit 0 and nothing installed"
fi

# A checksum mismatch installs nothing.
BAD_CHECKSUM=1 run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 1 ] && grep -q "Checksum mismatch" <<< "$output" && ! grep -q "install" <<< "$log"; then
	pass "checksum mismatch: fails and installs nothing"
else
	fail "checksum mismatch: fails and installs nothing"
fi

# #1437: the checksum of the fixture APK run_headset writes, and a different one.
fixture_sha="$(printf '%s\n' "Not a real APK: a fixture for tools/test_device_acceptance.sh." | sha256sum | cut -d' ' -f1)"
other_sha="1111111111111111111111111111111111111111111111111111111111111111"
passing_log="$(write_log pass 'Meltdown: acceptance: exit 0')"

# #1437: the headset already holds the release's build: no copy, no install,
# one line saying so, and the suite still runs.
HEADSET_SHA="$fixture_sha" run_headset "SERIAL1\tdevice\n" "$passing_log"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& grep -qxF "Headset SERIAL1 already has this build (checksum ${fixture_sha:0:12} matches); skipping download and install." <<< "$output" \
	&& grep -q -- "-s SERIAL1 shell pm path io.github.nolesszz.meltdown" <<< "$log" \
	&& ! grep -q " install " <<< "$log" && ! grep -q "Checksum verified" <<< "$output" \
	&& [ ! -e "$tmp/meltdown-apk-cache" ] && grep -q "am start" <<< "$log"; then
	pass "same checksum on the headset: no download, no install, the suite runs"
else
	fail "same checksum on the headset: no download, no install, the suite runs"
fi

# #1437: never skip on doubt. A different build, no package, a failing
# `pm path` or no sha256sum on the headset all install.
for case in "other:$other_sha:" "missing::" "pmfail:$fixture_sha:fail" "nosum:$fixture_sha:nosum"; do
	IFS=: read -r name sha pm <<< "$case"
	HEADSET_SHA="$sha" PM="$pm" run_headset "SERIAL1\tdevice\n" "$passing_log"
	if [ "$status" -eq 0 ] && [ "$(grep -c -- "-s SERIAL1 install -r " <<< "$log")" -eq 1 ] \
		&& grep -q "Checksum verified" <<< "$output" && ! grep -q "skipping download" <<< "$output"; then
		pass "headset build check '$name': installs"
	else
		fail "headset build check '$name': installs"
	fi
done

# #1437: -Force and MELTDOWN_FORCE_INSTALL=1 install over the same build
# without asking the headset.
for how in switch env; do
	if [ "$how" = "switch" ]; then
		HEADSET_SHA="$fixture_sha" EXTRA_ARGS="-Force" run_headset "SERIAL1\tdevice\n" "$passing_log"
	else
		HEADSET_SHA="$fixture_sha" FORCE_ENV=1 run_headset "SERIAL1\tdevice\n" "$passing_log"
	fi
	if [ "$status" -eq 0 ] && [ "$(grep -c -- "install -r " <<< "$log")" -eq 1 ] \
		&& ! grep -q "pm path" <<< "$log" && grep -q "Installing whatever the headset holds" <<< "$output"; then
		pass "force by $how: installs the same build"
	else
		fail "force by $how: installs the same build"
	fi
done

# #1437: a rerun after a failed install takes the APK from the cache, and the
# cache keeps only the current build.
INSTALLS="full" run_headset "SERIAL1\tdevice\n" "$passing_log"
first_tmp="$tmp"
if [ "$status" -eq 1 ] && grep -q "INSTALL_FAILED_INSUFFICIENT_STORAGE" <<< "$output" \
	&& grep -qF "By hand: adb -s SERIAL1 install -r \"$first_tmp/meltdown-apk-cache/$fixture_sha/meltdown-quest-debug.apk\"" <<< "$output"; then
	pass "failed install: the manual command names the kept APK"
else
	fail "failed install: the manual command names the kept APK"
fi
mkdir -p "$first_tmp/meltdown-apk-cache/$other_sha"
CACHE_FROM="$first_tmp" run_headset "SERIAL1\tdevice\n" "$passing_log"
if [ "$status" -eq 0 ] && [ -f "$first_tmp/meltdown-apk-cache/$fixture_sha/meltdown-quest-debug.apk" ] \
	&& grep -qxF "Using the copy already downloaded (${fixture_sha:0:12})." <<< "$output" \
	&& ! grep -q "Checksum verified" <<< "$output" \
	&& [ "$(grep -c -- "install -r " <<< "$log")" -eq 1 ] \
	&& [ "$(ls "$tmp/meltdown-apk-cache")" = "$fixture_sha" ]; then
	pass "rerun after a failed install: cached APK used, older builds deleted"
else
	fail "rerun after a failed install: cached APK used, older builds deleted"
fi

# Line number of the first adb call matching $1, or 999999 when there is none.
line_of() {
	local found
	found="$(grep -n -m 1 -- "$1" <<< "$log" | cut -d: -f1)"
	echo "${found:-999999}"
}

# A passing suite, still running for two polls. Screenshots come while it runs
# and show the game; the log is cleared, enlarged and streamed before the start.
EARLY_LOG="$(write_running_log)" EARLY_POLLS=2 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] && [ -f "$out/m1.json" ] \
	&& compgen -G "$out/screenshots/01-*s.png" > /dev/null \
	&& ! compgen -G "$out/screenshots/*-background.png" > /dev/null \
	&& ! grep -q "no screenshot was taken" <<< "$output" \
	&& grep -q "stub stream" "$out/device.log" && grep -q "Godot Engine" "$out/device.log" \
	&& [ "$(line_of "wait-for-device")" -lt "$(line_of "install -r")" ] \
	&& [ "$(line_of "logcat -G 16M")" -lt "$(line_of "logcat -c")" ] \
	&& [ "$(line_of "logcat -c")" -lt "$(line_of "logcat -v threadtime")" ] \
	&& [ "$(line_of "logcat -v threadtime")" -lt "$(line_of "am start")" ] \
	&& grep -q -- "-s SERIAL1 install -r" <<< "$log" \
	&& grep -q -- "am start -n io.github.nolesszz.meltdown/com.godot.game.GodotAppLauncher --es meltdown_acceptance m1" <<< "$log" \
		&& [ "$(grep -c -- "resolve-activity" <<< "$log")" -eq 1 ] && ! grep -q "Fell back" <<< "$output" \
	&& grep -q -- "settings put global stay_on_while_plugged_in 7" <<< "$log" \
	&& grep -q -- "settings put global stay_on_while_plugged_in 2" <<< "$log" \
	&& grep -q -- "automation_disable" <<< "$log" \
	&& grep -q "| m1 | basic_flight | pass |" <<< "$output" \
	&& grep -q "| m1 | frame_budget | pass: 90.0 Hz, 2700 frames: p99 11.40 ms |" <<< "$output"; then
	pass "passing suite: report, streamed log, screenshot in game, table, headset restored"
else
	fail "passing suite: report, streamed log, screenshot in game, table, headset restored"
fi

# A suite that ends before the first screenshot: no picture of whatever the
# headset shows after the game exits, and the summary warns.
run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& ! compgen -G "$out/screenshots/*.png" > /dev/null \
	&& grep -q "Warning: no screenshot was taken while the game was in the foreground" "$(dirname "$out")/summary.md" \
	&& grep -q "::warning" <<< "$output"; then
	pass "suite ends before the first screenshot: none taken after the exit, summary warns"
else
	fail "suite ends before the first screenshot: none taken after the exit, summary warns"
fi

# A locked or sleeping headset: a clean skip that says so, nothing started, the headset restored.
for lock in keyguard asleep; do
	LOCKED="$lock" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
	if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "skipped" ] \
		&& grep -q "Put the headset on and unlock it" <<< "$output" \
		&& grep -q "unattended nightly run needs the headset left unlocked" <<< "$output" \
		&& ! grep -q "am start" <<< "$log" && grep -q -- "stay_on_while_plugged_in 2" <<< "$log"; then
		pass "headset $lock: skipped with exit 0, nothing started, headset restored"
	else
		fail "headset $lock: skipped with exit 0, nothing started, headset restored"
	fi
done

# A lock the dumpsys flags miss: the game never reaches the foreground and no
# step starts, so the run skips instead of waiting out the timeout.
BACKGROUND=1 EARLY_LOG="Godot Engine v4.7.2.stable.official" EARLY_POLLS=99 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "skipped" ] \
	&& grep -q "never reached the foreground" <<< "$output" \
	&& grep -q -- "stay_on_while_plugged_in 2" <<< "$log"; then
	pass "game never in the foreground: skipped with exit 0, headset restored"
else
	fail "game never in the foreground: skipped with exit 0, headset restored"
fi

# A failing step fails the job and is named.
run_headset "SERIAL1\tdevice\n" "$(write_log fail 'Meltdown: acceptance: exit 1')"
if [ "$status" -eq 1 ] && [ "$(status_of "$out")" = "failed" ] && grep -q "failed steps: m1/basic_flight" <<< "$output"; then
	pass "failing step: exit 1 naming suite and step"
else
	fail "failing step: exit 1 naming suite and step"
fi

# The game stops without a report.
DEAD=1 run_headset "SERIAL1\tdevice\n" "Godot Engine v4.7.2.stable.official"
if [ "$status" -eq 1 ] && grep -q "stopped before it printed a report" <<< "$output" \
	&& grep -q -- "stay_on_while_plugged_in 2" <<< "$log"; then
	pass "no report: exit 1 and the headset is restored"
else
	fail "no report: exit 1 and the headset is restored"
fi

# An install that fails without a reason, then with the headset gone (#589,
# #590), waits for the headset each time and goes on to the suite. The first
# wait is before the build check (#1437), the next three around the installs.
INSTALLS="blank notfound ok" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& [ "$(grep -c -- "install -r --no-streaming" <<< "$log")" -eq 2 ] \
	&& [ "$(grep -c -- "wait-for-device" <<< "$log")" -eq 4 ] \
	&& grep -q "dropped off USB for a moment; waiting" <<< "$output" \
	&& grep -q "am start" <<< "$log"; then
	pass "blank, then not found, then installed: waits, retries and runs the suite"
else
	fail "blank, then not found, then installed: waits, retries and runs the suite"
fi

# A headset that stays gone fails the install with the plain message, not the suite.
INSTALLS="notfound" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 1 ] && [ "$(status_of "$out")" = "failed" ] \
	&& grep -q "Install failed on SERIAL1: the headset dropped off USB for a moment and was not back in time" <<< "$output" \
	&& [ "$(grep -c -- "install -r" <<< "$log")" -eq 3 ] && ! grep -q "am start" <<< "$log"; then
	pass "headset never back: install fails with the plain message after two retries"
else
	fail "headset never back: install fails with the plain message after two retries"
fi

# A headset that never reappears for wait-for-device is given up on in time.
WAIT=hang DEVICE_WAIT=1 run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 1 ] && grep -q "Install failed on SERIAL1: the headset dropped off USB" <<< "$output" \
	&& ! grep -q "install -r" <<< "$log"; then
	pass "wait-for-device hangs: gives up after the wait, installs nothing"
else
	fail "wait-for-device hangs: gives up after the wait, installs nothing"
fi

launcher="am start -n io.github.nolesszz.meltdown/com.godot.game.GodotAppLauncher --es meltdown_acceptance m1"

# The activity lookup prints nothing usable right after an install (#1392): it
# is asked three times, then the exported launcher is started and the output
# says it fell back and why.
RESOLVES="empty" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& [ "$(grep -c -- "resolve-activity" <<< "$log")" -eq 3 ] \
	&& grep -q "Fell back to io.github.nolesszz.meltdown/com.godot.game.GodotAppLauncher because the activity lookup printed no activity on all 3 tries" <<< "$output" \
	&& [ "$(grep -c -- "am start" <<< "$log")" -eq 1 ] && grep -q -- "$launcher" <<< "$log"; then
	pass "empty activity lookup: asked three times, falls back to the launcher and says so"
else
	fail "empty activity lookup: asked three times, falls back to the launcher and says so"
fi

# An empty answer, then a usable one: the second try is used and nothing falls back.
RESOLVES="empty ok" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(grep -c -- "resolve-activity" <<< "$log")" -eq 2 ] \
	&& ! grep -q "Fell back" <<< "$output" && grep -q -- "$launcher" <<< "$log"; then
	pass "activity lookup empty once: retried, no fallback"
else
	fail "activity lookup empty once: retried, no fallback"
fi

# The lookup names an activity Android will not start from adb: the start is
# retried once with the launcher and the suite runs (#1392).
RESOLVED="com.godot.game.GodotApp" NOT_EXPORTED="com.godot.game.GodotApp" \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& grep -q "refused io.github.nolesszz.meltdown/com.godot.game.GodotApp as not exported; trying" <<< "$output" \
	&& [ "$(grep -c -- "am start" <<< "$log")" -eq 2 ] && grep -q -- "$launcher" <<< "$log"; then
	pass "activity not exported: retried once with the launcher, suite runs"
else
	fail "activity not exported: retried once with the launcher, suite runs"
fi

# The launcher itself refused: no second retry, the suite fails saying why.
RESOLVES="empty" NOT_EXPORTED="com.godot.game.GodotAppLauncher" \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 1 ] && [ "$(status_of "$out")" = "failed" ] \
	&& grep -q "The game did not start" <<< "$output" && [ "$(grep -c -- "am start" <<< "$log")" -eq 1 ]; then
	pass "launcher refused: fails once, no retry loop"
else
	fail "launcher refused: fails once, no retry loop"
fi

# Adb drops, reports from the game's storage, the serial and unattended runs (#1436).
# shellcheck source=tools/device_acceptance_drop_checks.sh
source "$tools/device_acceptance_drop_checks.sh"
# Live progress lines while a suite runs (#1438).
# shellcheck source=tools/device_acceptance_progress_checks.sh
source "$tools/device_acceptance_progress_checks.sh"
# The wait for the exit line, from the suites asked for (#1504).
# shellcheck source=tools/device_acceptance_wait_checks.sh
source "$tools/device_acceptance_wait_checks.sh"

# The simulator job skips cleanly away from Windows.
sim_out="$work/simulator"
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/simulator_acceptance.ps1" -Suite m1 -OutDir "$sim_out" 2>&1)" || status=$?
if [ "$status" -eq 0 ] && [ "$(status_of "$sim_out")" = "skipped" ] && grep -q "Not on Windows" <<< "$output"; then
	pass "simulator off Windows: skipped with exit 0"
else
	fail "simulator off Windows: skipped with exit 0"
fi

# The report job (post_acceptance.ps1): one failing and one passing set of
# results, checked by post_acceptance_checks.sh so this file stays short.
results="$work/results"
mkdir -p "$results/simulator"
run_headset "SERIAL1\tdevice\n" "$(write_log fail 'Meltdown: acceptance: exit 1')"
cp -r "$out" "$results/headset"
cp "$sim_out/result.json" "$results/simulator/"
passing="$work/passing"
mkdir -p "$passing/simulator"
run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
cp -r "$out" "$passing/headset"
cp "$sim_out/result.json" "$passing/simulator/"
if ! "$tools/post_acceptance_checks.sh" "$results" "$passing"; then
	failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "All device acceptance checks passed"
