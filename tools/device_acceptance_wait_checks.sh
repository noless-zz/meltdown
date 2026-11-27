# shellcheck shell=bash
# The variables run_headset sets ($status, $output) and $work and $tools come
# from test_device_acceptance.sh.
# shellcheck disable=SC2154
# Sourced by test_device_acceptance.sh, whose run_headset, pass and fail it
# uses (#1504): the wait for the exit line comes from the suites asked for.

game="$(cd "$tools/.." && pwd)/game"

# The ticks a replay flies: its lines after `inputs`, blank and `#` lines left out.
replay_ticks() {
	local path="$game/${1#res://}"
	if [ ! -f "$path" ]; then
		echo 0
		return
	fi
	awk '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
		$0 == "" || /^#/ { next }
		body { ticks++; next }
		$0 == "inputs" { body = 1 }
		END { print ticks + 0 }' "$path"
}

# The nightly suite's step limits summed here with jq and awk, apart from
# acceptance_wait.ps1, by the rule in game/acceptance/acceptance_time_limit.gd.
nightly_limits() {
	local suites="$game/acceptance/suites" total="0" file default part steps step
	for file in "$suites"/*.json; do
		if [ "$(jq -r '.manual_only // false' "$file")" = "true" ]; then
			continue
		fi
		default="$(jq -r '.default_time_limit_seconds // 120' "$file")"
		steps="$(jq -c '.steps[]?' "$file")"
		for part in $(jq -r '.include[]?' "$file"); do
			steps+=$'\n'"$(jq -c '.steps[]?' "$suites/$part.json")"
		done
		while IFS= read -r step; do
			[ -n "$step" ] || continue
			local own waits ticks=0 path
			own="$(jq -r '.time_limit_seconds // empty' <<< "$step")"
			if [ -n "$own" ]; then
				total="$(awk -v a="$total" -v b="$own" 'BEGIN { printf "%.6f", a + b }')"
				continue
			fi
			waits="$(jq -r '[.settle_seconds, .measure_seconds, .view_seconds, .pause_seconds] | map(. // 0) | add' <<< "$step")"
			if [ "$(jq -r '.loop_replay // false' <<< "$step")" != "true" ]; then
				for path in $(jq -r '.replay // empty, .next_replay // empty' <<< "$step"); do
					ticks=$((ticks + $(replay_ticks "$path")))
				done
			fi
			total="$(awk -v a="$total" -v d="$default" -v w="$waits" -v t="$ticks" 'BEGIN { printf "%.6f", a + d + w + t / 72 }')"
		done <<< "$steps"
	done
	echo "$total"
}

# What Get-AcceptanceWait gives for a suite: "<Seconds> <Sum> <Margin> <Suites> <Problem>".
wait_script="$work/wait_check.ps1"
cat > "$wait_script" <<'PS1'
param([string]$Tools, [string]$Suite, [string]$GameDir)
$ErrorActionPreference = 'Stop'
. (Join-Path $Tools 'acceptance_wait.ps1')
$wait = Get-AcceptanceWait -Suite $Suite -GameDir $GameDir
$problem = if ($wait.Problem) { 'problem' } else { 'none' }
Write-Output ('{0} {1} {2} {3} {4}' -f $wait.Seconds, [Math]::Round($wait.Sum, 3), $wait.Margin, ($wait.Suites -join ','), $problem)
PS1
wait_for() {
	pwsh -NoProfile -NonInteractive -File "$wait_script" -Tools "$tools" -Suite "$1" -GameDir "${2:-$game}"
}

# -Suite nightly: a wait longer than the sum of its steps' limits, and longer
# than the 900 s that cut the 27 Nov run off in m3.
expected="$(nightly_limits)"
read -r seconds sum margin names problem <<< "$(wait_for nightly)"
output="nightly: wait $seconds s, sum $sum s (here $expected s), margin $margin s, suites $names, $problem"
if [ "$problem" = "none" ] && [ "$margin" -gt 0 ] \
	&& awk -v w="$seconds" -v s="$expected" -v p="$sum" 'BEGIN { exit !(w > s && w > 900 && (p - s) ^ 2 < 1) }' \
	&& [[ ",$names," == *",m6,"* ]] && [[ ",$names," != *",soak,"* ]]; then
	pass "wait: -Suite nightly waits longer than the sum of its steps' limits ($seconds s > $expected s), soak left out"
else
	fail "wait: -Suite nightly waits longer than the sum of its steps' limits"
fi

# The rule on made-up suites: a step's own limit, the suite default plus the
# waits and the replay's flight at 72 Hz, a looped replay, an included part,
# a manual-only suite left out of nightly, and a suite with no file.
fake="$work/fake_game"
mkdir -p "$fake/acceptance/suites/a"
cat > "$fake/acceptance/suites/a.json" <<'JSON'
{"name": "a", "default_time_limit_seconds": 10, "include": ["a/p"], "steps": [
	{"id": "own", "time_limit_seconds": 7, "settle_seconds": 50},
	{"id": "flies", "settle_seconds": 2, "replay": "res://r.replay"}]}
JSON
echo '{"steps": [{"id": "loops", "loop_replay": true, "measure_seconds": 5, "replay": "res://r.replay"}]}' \
	> "$fake/acceptance/suites/a/p.json"
echo '{"name": "b", "manual_only": true, "steps": [{"id": "soaks"}]}' > "$fake/acceptance/suites/b.json"
{
	printf 'meltdown-replay 1\nseed 1\nships 1\ninputs\n'
	for _ in $(seq 144); do echo '0 0 0 0 0 0'; done
	printf '\n# a comment\n'
} > "$fake/r.replay"
output="nightly $(wait_for nightly "$fake") | all $(wait_for all "$fake") | a $(wait_for a "$fake") | q $(wait_for q "$fake")"
if [ "$output" = "nightly 336 36 300 a none | all 456 156 300 a,b none | a 336 36 300 a none | q 3600 0 300  problem" ]; then
	pass "wait: own limits, waits, replay flight, looped replays, parts, manual-only suites and a missing suite"
else
	fail "wait: own limits, waits, replay flight, looped replays, parts, manual-only suites and a missing suite"
fi

# With no -TimeoutSeconds the run says its wait; a -TimeoutSeconds overrides it.
TIMEOUT=0 run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
derived="$output"
run_headset "SERIAL1\tdevice\n" "$(write_log pass 'Meltdown: acceptance: exit 0')"
if [ "$status" -eq 0 ] && grep -Eq '^Waiting up to [0-9]+ s for the exit line: the step time limits of m1 add up to [0-9]+ s, plus 300 s margin' <<< "$derived" \
	&& ! grep -q 'Waiting up to' <<< "$output"; then
	pass "wait: the run says the wait it worked out, and -TimeoutSeconds overrides it"
else
	output="$derived"$'\n'"$output"
	fail "wait: the run says the wait it worked out, and -TimeoutSeconds overrides it"
fi
