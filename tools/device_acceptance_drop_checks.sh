# shellcheck shell=bash
# The variables run_headset sets ($status, $output, $out, $log) and $work come
# from test_device_acceptance.sh.
# shellcheck disable=SC2154
# Sourced by test_device_acceptance.sh, whose run_headset, write_log, pass and
# fail it uses (#1436): an adb drop mid-suite, reports read from the game's
# storage, a partial table, the serial to use and unattended runs.

# The game's log after both m1 steps ended, without the report or exit line
# (the stream was cut before them).
write_steps_log() {
	echo "Godot Engine v4.7.2.stable.official"
	echo "Meltdown: acceptance: step basic_flight"
	echo "Meltdown: acceptance: step basic_flight pass"
	echo "Meltdown: acceptance: step frame_budget"
	echo "Meltdown: acceptance: step frame_budget ${1:-pass}"
}

# The headset resets its USB mid-suite and is back two device listings later:
# no crash verdict, the wait is said, and the full table comes from the log.
EARLY_LOG="$(write_running_log)" EARLY_POLLS=3 DROP_AT=2 DROP_FOR=2 TIMEOUT=60 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& grep -Eq "the connection to the headset dropped at [0-9]{2}:[0-9]{2}:[0-9]{2}" <<< "$output" \
	&& grep -Eq "the headset is back at [0-9]{2}:[0-9]{2}:[0-9]{2}" <<< "$output" \
	&& ! grep -q "stopped before it printed a report" <<< "$output" \
	&& grep -q "| m1 | basic_flight | pass |" <<< "$output" \
	&& grep -q "| m1 | frame_budget | pass: 90.0 Hz" <<< "$output" \
	&& grep -q "the stream ended at an adb drop" "$out/device.log"; then
	pass "adb drop and return mid-suite: waits, goes on, full table"
else
	fail "adb drop and return mid-suite: waits, goes on, full table"
fi

# The headset never comes back: the verdict is the drop, with the steps seen
# so far as a partial table, not a step verdict from a partial log.
EARLY_LOG="$(write_steps_log)" EARLY_POLLS=99 DROP_AT=2 RECONNECT=1 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 1 ] && [ "$(status_of "$out")" = "failed" ] \
	&& grep -Eq "Device acceptance failed::the connection to the headset dropped at [0-9:]{8} and the headset was not back within 1 s" <<< "$output" \
	&& grep -q "the table is partial" <<< "$output" \
	&& ! grep -q "failed steps" <<< "$output" && ! grep -q "stopped before" <<< "$output" \
	&& grep -q "| m1 | frame_budget | pass |" <<< "$output"; then
	pass "adb drop that never returns: dropped verdict with a partial table"
else
	fail "adb drop that never returns: dropped verdict with a partial table"
fi

# The log lost the report and exit line, but the game's storage has both: the
# reports are cleared before the start, pulled at the end and give the table.
files="$work/game-files"
mkdir -p "$files"
write_log pass "" | sed -n '/MELTDOWN_ACCEPTANCE_BEGIN/,/MELTDOWN_ACCEPTANCE_END/p' \
	| sed '1d;$d' > "$files/m1-2c68c89.json"
sleep 1
echo '{"build": "2c68c89", "suites": ["m1"], "passed": 1, "failed": 0, "skipped": 0, "exit_code": 0}' \
	> "$files/acceptance_exit.json"
GAME_FILES="$files" run_headset "SERIAL1\tdevice\n" "$(write_steps_log)"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "passed" ] \
	&& [ -f "$out/from-headset/m1-2c68c89.json" ] && [ -f "$out/from-headset/acceptance_exit.json" ] \
	&& grep -q "acceptance_exit.json stands for exit 0" <<< "$output" \
	&& grep -q "| m1 | frame_budget | pass: 90.0 Hz, 2700 frames: p99 11.40 ms |" <<< "$output" \
	&& ! grep -q "partial" <<< "$output" \
	&& [ "$(line_of "run-as io.github.nolesszz.meltdown rm -rf files/acceptance")" -lt "$(line_of "am start")" ]; then
	pass "reports pulled from the game's storage at the end give the table"
else
	fail "reports pulled from the game's storage at the end give the table"
fi

# No exit line and no exit file: a partial table from the step lines, said so.
run_headset "SERIAL1\tdevice\n" "$(write_steps_log fail)"
if [ "$status" -eq 1 ] && [ "$(status_of "$out")" = "failed" ] \
	&& grep -q "failed steps: m1/frame_budget" <<< "$output" \
	&& grep -q "the table is partial" <<< "$output" \
	&& grep -q "| m1 | basic_flight | pass |" <<< "$output"; then
	pass "no exit line and no exit file: partial table from the step lines"
else
	fail "no exit line and no exit file: partial table from the step lines"
fi

# ANDROID_SERIAL is honoured, and -Serial over it.
SERIAL_ENV=SERIAL2 run_headset "SERIAL1\tdevice\nSERIAL2\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -q -- "-s SERIAL2 install -r" <<< "$log" && ! grep -q -- "-s SERIAL1 install" <<< "$log" \
	&& grep -q "named by ANDROID_SERIAL" <<< "$output"; then
	pass "ANDROID_SERIAL picks the headset"
else
	fail "ANDROID_SERIAL picks the headset"
fi
SERIAL_ENV=SERIAL1 EXTRA_ARGS="-Serial SERIAL2" \
	run_headset "SERIAL1\tdevice\nSERIAL2\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -q -- "-s SERIAL2 shell am start" <<< "$log" \
	&& grep -q "named by -Serial" <<< "$output"; then
	pass "-Serial picks the headset over ANDROID_SERIAL"
else
	fail "-Serial picks the headset over ANDROID_SERIAL"
fi
SERIAL_ENV=GONE run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && [ "$(status_of "$out")" = "skipped" ] && grep -q "GONE, named by ANDROID_SERIAL, is not among" <<< "$output" \
	&& ! grep -q "install" <<< "$log"; then
	pass "a named headset that is not connected: skipped, nothing installed"
else
	fail "a named headset that is not connected: skipped, nothing installed"
fi

# The same headset on the cable and on Wi-Fi, none named: Wi-Fi, and it says so.
HARDWARE="2G97C5ZJ2J0151=HW1 192.168.1.5:5555=HW1" \
	run_headset "2G97C5ZJ2J0151\tdevice\n192.168.1.5:5555\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -q -- "-s 192.168.1.5:5555 install -r" <<< "$log" \
	&& grep -q "on the cable (2G97C5ZJ2J0151) and on Wi-Fi; using Wi-Fi 192.168.1.5:5555" <<< "$output"; then
	pass "same headset on cable and Wi-Fi: Wi-Fi is used and named"
else
	fail "same headset on cable and Wi-Fi: Wi-Fi is used and named"
fi

# Unattended runs tell the game, so sleeping controllers skip; attended ones do not.
for case_args in "-Unattended|1" "EVENT=schedule|1" "|0"; do
	EVENT="" EXTRA_ARGS=""
	case "${case_args%%|*}" in
		-Unattended) EXTRA_ARGS="-Unattended" ;;
		EVENT=*) EVENT="${case_args%%|*}"; EVENT="${EVENT#EVENT=}" ;;
	esac
	EVENT="$EVENT" EXTRA_ARGS="$EXTRA_ARGS" \
		run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
	found=0
	if grep -q -- "--es meltdown_acceptance m1 --es meltdown_unattended 1" <<< "$log"; then
		found=1
	fi
	if [ "$status" -eq 0 ] && [ "$found" = "${case_args##*|}" ]; then
		pass "unattended extra for '${case_args%%|*}': ${case_args##*|}"
	else
		fail "unattended extra for '${case_args%%|*}': ${case_args##*|}"
	fi
done
EVENT="" EXTRA_ARGS=""
