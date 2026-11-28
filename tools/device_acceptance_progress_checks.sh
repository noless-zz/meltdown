# shellcheck shell=bash
# The variables run_headset sets ($status, $output) and $work come from
# test_device_acceptance.sh.
# shellcheck disable=SC2154
# Sourced by test_device_acceptance.sh, whose run_headset, write_log,
# write_running_log, pass and fail it uses (#1438): the live progress lines
# device_acceptance.ps1 prints while a suite runs on the headset.

# The line number in $output of the first line matching the extended regex $1.
output_line_of() {
	local found
	found="$(grep -n -m 1 -E -- "$1" <<< "$output" | cut -d: -f1)"
	echo "${found:-999999}"
}

# A step starts on an early poll and ends on a later one: one running line,
# then its result with how long it took, then the suite's summary.
EARLY_LOG="$(write_running_log)" EARLY_POLLS=2 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
running="$(output_line_of '^\[00:0[0-9]\] m1  1  basic_flight \.\.\. running$')"
ended="$(output_line_of '^\[00:0[0-9]\] m1  1  basic_flight     PASS  \([0-9]+ s\)$')"
if [ "$status" -eq 0 ] && [ "$(grep -c '^== m1 ==$' <<< "$output")" -eq 1 ] \
	&& [ "$(grep -c 'basic_flight \.\.\. running' <<< "$output")" -eq 1 ] \
	&& [ "$running" -lt "$ended" ] && [ "$ended" -lt "$(output_line_of '^== m1: 2 passed, 0 failed ==$')" ] \
	&& [ "$(output_line_of '^== m1: 2 passed')" -lt 999999 ]; then
	pass "progress: a step's start, its end with the time it took, and the suite summary, each once"
else
	fail "progress: a step's start, its end with the time it took, and the suite summary, each once"
fi

# A failed step: its end line says FAIL and the summary names it with its message.
run_headset "SERIAL1\tdevice\n" "$(write_log fail 'Meltdown: acceptance: exit 1')"
if [ "$status" -eq 1 ] && grep -Eq '^\[00:0[0-9]\] m1  1  basic_flight     FAIL  \([0-9]+ s\)$' <<< "$output" \
	&& grep -qxF '== m1: 1 passed, 1 failed ==' <<< "$output" \
	&& grep -qxF '   FAIL m1/basic_flight: final_hash: final hash 861662111' <<< "$output"; then
	pass "progress: a failed step and the suite's failure with the step message"
else
	fail "progress: a failed step and the suite's failure with the step message"
fi

# The step lines with #1444's fields: the number and count, and the time-out message.
fields_log="Godot Engine v4.7.2.stable.official
Meltdown: acceptance: step basic_flight suite=m1 index=1 count=2
Meltdown: acceptance: step basic_flight fail suite=m1 index=1 count=2 (ran out of its 120 s at tick 50)
Meltdown: acceptance: step frame_budget suite=m1 index=2 count=2
Meltdown: acceptance: step frame_budget pass suite=m1 index=2 count=2
Meltdown: acceptance: exit 1"
run_headset "SERIAL1\tdevice\n" "$fields_log"
if grep -Eq '^\[00:0[0-9]\] m1  1/2  basic_flight \.\.\. running$' <<< "$output" \
	&& grep -Eq '^\[00:0[0-9]\] m1  1/2  basic_flight     FAIL  \([0-9]+ s\): ran out of its 120 s at tick 50$' <<< "$output" \
	&& grep -Eq '^\[00:0[0-9]\] m1  2/2  frame_budget     PASS' <<< "$output"; then
	pass "progress: suite, number and count from the step line's fields, and a time-out's message"
else
	fail "progress: suite, number and count from the step line's fields, and a time-out's message"
fi

# The drop and return lines carry the time since the start too.
EARLY_LOG="$(write_running_log)" EARLY_POLLS=3 DROP_AT=2 DROP_FOR=2 TIMEOUT=60 \
	run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if grep -Eq '^\[00:[0-9]{2}\] Waiting up to 5 s: the connection to the headset dropped at' <<< "$output" \
	&& grep -Eq '^\[00:[0-9]{2}\] Going on: the headset is back at' <<< "$output"; then
	pass "progress: the drop and return lines start with the time since the start"
else
	fail "progress: the drop and return lines start with the time since the start"
fi

# #1504: a recorded log in which steps 3 to 13 of m1 end within one poll, and
# the headset's log buffer has dropped steps 1 and 2 since the poll before.
# Counting events from the front skipped as many new steps as old lines were
# dropped; every step must get its end line, once, and its start line at most once.
wrap_ids=(basic_flight refresh_rate frame_budget flight_axes comfort_preset_3 comfort_preset_4
	comfort_preset_1 comfort_preset_2 view_not_flat afterburner preset_change_mid_flight
	first_launch_flight_test reset_to_start)
EARLY_LOG="$(cat "$fixtures/progress_wrap_early.log")" EARLY_POLLS=1 \
	run_headset "SERIAL1\tdevice\n" "$(cat "$fixtures/progress_wrap_late.log")"
wrap_missing=""
for index in "${!wrap_ids[@]}"; do
	id="${wrap_ids[$index]}"
	ends="$(grep -cE "^\[[0-9]{2}:[0-9]{2}\] m1  $((index + 1))/13  $id     PASS  \([0-9]+ s\)$" <<< "$output" || true)"
	starts="$(grep -cE "^\[[0-9]{2}:[0-9]{2}\] m1  $((index + 1))/13  $id \.\.\. running$" <<< "$output" || true)"
	if [ "$ends" -ne 1 ] || [ "$starts" -gt 1 ]; then
		wrap_missing+=" $id($ends end, $starts start)"
	fi
done
if [ "$status" -eq 0 ] && [ -z "$wrap_missing" ] && [ "$(grep -c '     PASS' <<< "$output")" -eq 13 ] \
	&& grep -qxF '== m1: 13 passed, 0 failed ==' <<< "$output"; then
	pass "progress: every step that ends within one poll gets its line, after the log buffer dropped old lines"
else
	output+=$'\n'"steps without exactly one end line:$wrap_missing"
	fail "progress: every step that ends within one poll gets its line, after the log buffer dropped old lines"
fi

# The lines themselves, with colours and several suites, straight from the functions.
progress_script="$work/progress_check.ps1"
cat > "$progress_script" <<'PS1'
param([string]$Tools)
$ErrorActionPreference = 'Stop'
. (Join-Path $Tools 'acceptance_common.ps1')
. (Join-Path $Tools 'acceptance_progress.ps1')
$problems = @()
$state = New-ProgressState -Suite 'all'
$log = @('Meltdown: acceptance: step boot')
$first = Get-ProgressLines -State $state -Lines $log -Elapsed 17.4
$log += @('Meltdown: acceptance: step boot fail', 'MELTDOWN_ACCEPTANCE_BEGIN',
	'{"suite": "m0", "steps": [{"id": "boot", "result": "fail", "message": "no_script_errors: 2 errors"}]}',
	'MELTDOWN_ACCEPTANCE_END', 'Meltdown: acceptance: step basic_flight')
$second = Get-ProgressLines -State $state -Lines $log -Elapsed 50.2
$again = Get-ProgressLines -State $state -Lines $log -Elapsed 55
$expected = @(
	@('== suite 1 ==', 'Cyan'),
	@('[00:17] suite 1  1  boot ... running', $null),
	@('[00:50] suite 1  1  boot     FAIL  (33 s)', 'Red'),
	@('== m0: 0 passed, 1 failed ==', 'Red'),
	@('   FAIL m0/boot: no_script_errors: 2 errors', 'Red'),
	@('== suite 2 ==', 'Cyan'),
	@('[00:50] suite 2  1  basic_flight ... running', $null)
)
$got = @($first) + @($second)
if ($got.Count -ne $expected.Count) {
	$problems += "got $($got.Count) lines: $(($got | ForEach-Object { $_.Text }) -join ' | ')"
} else {
	for ($i = 0; $i -lt $expected.Count; $i++) {
		if ($got[$i].Text -ne $expected[$i][0] -or $got[$i].Color -ne $expected[$i][1]) {
			$problems += "line $i is '$($got[$i].Text)' in $($got[$i].Color), not '$($expected[$i][0])' in $($expected[$i][1])"
		}
	}
}
if (@($again).Count -ne 0) {
	$problems += 'a poll with no new lines printed again'
}
if ((Format-ProgressTime 3725.9) -ne '[62:05]') {
	$problems += "an hour in reads $(Format-ProgressTime 3725.9)"
}
$named = New-ProgressState -Suite 'm6'
$line = @(Get-ProgressLines -State $named -Lines @('x', 'Meltdown: acceptance: step a pass') -Elapsed 1)
if ($line[0].Text -ne '== m6 ==' -or $line[1].Text -ne '[00:01] m6  1  a     PASS' -or $line[1].Color -ne 'Green') {
	$problems += "an end with no start: $(($line | ForEach-Object { $_.Text }) -join ' | ')"
}
if ($problems.Count -gt 0) {
	$problems | ForEach-Object { Write-Output $_ }
	exit 1
}
PS1
status=0
output="$(pwsh -NoProfile -NonInteractive -File "$progress_script" -Tools "$tools" 2>&1)" || status=$?
if [ "$status" -eq 0 ]; then
	pass "progress: lines, colours and suites from the functions, none repeated"
else
	fail "progress: lines, colours and suites from the functions, none repeated"
fi
