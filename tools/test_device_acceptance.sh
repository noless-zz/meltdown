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
		GITHUB_STEP_SUMMARY="$dir/summary.md" \
		pwsh -NoProfile -NonInteractive -File "$tools/device_acceptance.ps1" \
		-Suite m1 -OutDir "$out" -PollSeconds 0 -StartGraceSeconds 0 -TimeoutSeconds 3 \
		-WakeSeconds 0 -ForegroundGraceSeconds 0 -DeviceWaitSeconds "${DEVICE_WAIT:-5}" 2>&1)" || status=$?
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
	&& grep -q -- "am start -n io.github.nolesszz.meltdown/com.godot.game.GodotApp --es meltdown_acceptance m1" <<< "$log" \
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
# #590), waits for the headset each time and goes on to the suite.
INSTALLS="blank notfound ok" run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& [ "$(grep -c -- "install -r --no-streaming" <<< "$log")" -eq 2 ] \
	&& [ "$(grep -c -- "wait-for-device" <<< "$log")" -eq 3 ] \
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

# The simulator job skips cleanly away from Windows.
sim_out="$work/simulator"
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/simulator_acceptance.ps1" -Suite m1 -OutDir "$sim_out" 2>&1)" || status=$?
if [ "$status" -eq 0 ] && [ "$(status_of "$sim_out")" = "skipped" ] && grep -q "Not on Windows" <<< "$output"; then
	pass "simulator off Windows: skipped with exit 0"
else
	fail "simulator off Windows: skipped with exit 0"
fi

# The report job: one table with both columns; issues only on the nightly run.
results="$work/results"
mkdir -p "$results/simulator"
run_headset "SERIAL1\tdevice\n" "$(write_log fail 'Meltdown: acceptance: exit 1')"
cp -r "$out" "$results/headset"
cp "$sim_out/result.json" "$results/simulator/"
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/post_acceptance.ps1" -ResultsDir "$results" \
	-Suite m1 -EventName workflow_dispatch -Repository owner/repo -DryRun 2>&1)" || status=$?
if [ "$status" -eq 0 ] && grep -q "| Suite | Step | Headset | Simulator |" <<< "$output" \
	&& grep -q "| m1 | basic_flight | fail: final_hash: final hash 861662111 | not run |" <<< "$output" \
	&& ! grep -q "DRY RUN" <<< "$output"; then
	pass "report, manual run: both columns, no issue calls"
else
	fail "report, manual run: both columns, no issue calls"
fi
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$tools/post_acceptance.ps1" -ResultsDir "$results" \
	-Suite m1 -EventName schedule -Repository owner/repo -DryRun 2>&1)" || status=$?
if [ "$status" -eq 0 ] && grep -q "DRY RUN GET issues?state=open&labels=gate" <<< "$output" \
	&& grep -q "DRY RUN POST issues$" <<< "$output" \
	&& grep -q "Nightly device acceptance fails: headset m1/basic_flight" <<< "$output" \
	&& grep -q '"playtest"' <<< "$output"; then
	pass "report, nightly failure: opens a playtest issue naming suite and step"
else
	fail "report, nightly failure: opens a playtest issue naming suite and step"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "All device acceptance checks passed"
