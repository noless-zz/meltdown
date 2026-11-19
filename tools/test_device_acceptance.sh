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
	: > "$dir/adb.log"
	out="$dir/out"
	status=0
	output="$(PATH="$fixtures/bin:$PATH" \
		MELTDOWN_APK_DIR="$dir/release" \
		STUB_ADB_LOG="$dir/adb.log" \
		STUB_ADB_DEVICES="$devices" \
		STUB_GODOT_LOG="$dir/godot.log" \
		STUB_ADB_DEAD="${DEAD:-0}" \
		STUB_ADB_BLANK_INSTALL="${BLANK_INSTALL:-0}" \
		GITHUB_STEP_SUMMARY="$dir/summary.md" \
		pwsh -NoProfile -NonInteractive -File "$tools/device_acceptance.ps1" \
		-Suite m1 -OutDir "$out" -PollSeconds 0 -StartGraceSeconds 0 -TimeoutSeconds 3 2>&1)" || status=$?
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

# A passing suite.
run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] && [ -f "$out/m1.json" ] \
	&& [ -f "$out/device.log" ] && compgen -G "$out/screenshots/*.png" > /dev/null \
	&& grep -q -- "-s SERIAL1 install -r" <<< "$log" \
	&& grep -q -- "am start -n io.github.nolesszz.meltdown/com.godot.game.GodotApp --es meltdown_acceptance m1" <<< "$log" \
	&& grep -q -- "settings put global stay_on_while_plugged_in 7" <<< "$log" \
	&& grep -q -- "settings put global stay_on_while_plugged_in 2" <<< "$log" \
	&& grep -q -- "automation_disable" <<< "$log" \
	&& grep -q "| m1 | basic_flight | pass |" <<< "$output"; then
	pass "passing suite: report, log, screenshot, table, headset restored"
else
	fail "passing suite: report, log, screenshot, table, headset restored"
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

# An install that fails without a reason is retried once without streaming.
BLANK_INSTALL=1 run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -q -- "install -r --no-streaming" <<< "$log"; then
	pass "blank install failure: retried with --no-streaming"
else
	fail "blank install failure: retried with --no-streaming"
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
