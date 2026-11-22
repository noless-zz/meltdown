#!/usr/bin/env bash
# Checks tools/bot_run_rate.sh on made-up run sweep output, so a broken parser
# fails before the nightly bot-runs shards spend their time flying (#1174).
# The nightly workflow runs this first; it needs only bash and jq.
# Usage: tools/test_bot_run_rate.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bot_run_rate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

expect_output() {
	local name="$1" expected="$2"
	shift 2
	local output
	if output="$("$script" "$@" 2>&1)" && [ "$output" == "$expected" ]; then
		echo "ok   $name"
	else
		echo "FAIL $name: expected '$expected', got '$output'" >&2
		failures=$((failures + 1))
	fi
}

expect_refused() {
	local name="$1"
	shift
	if "$script" "$@" > /dev/null 2>&1; then
		echo "FAIL $name: the script accepted '$*'" >&2
		failures=$((failures + 1))
	else
		echo "ok   $name"
	fi
}

# One ship's lines as bot_run_sweep.gd prints them: a MELTDOWN_BOT_RUN line per
# run (LINES of them, RUNS by default), then the summary. LOSSES is the loss
# fields (#1195), by default every lost run destroyed on level 1.
# Usage: ship_lines SUFFIX FIRST RUNS COMPLETED FLOWN ESCAPED [LINES] [LOSSES]
ship_lines() {
	local suffix="$1" first="$2" runs="$3" completed="$4" flown="$5" escaped="$6"
	local lines="${7:-$3}" i
	local losses="${8:-$(losses "[$((runs - completed))]" "$((runs - completed))" 0 0)}"
	for ((i = 0; i < lines; i++)); do
		echo "MELTDOWN_BOT_RUN${suffix} {\"seed\":$((first + i)),\"planned\":4,\"flown\":1,\"escaped\":0,\"ended\":\"RUNNING ship destroyed\",\"robot_scales\":[1.00]}"
	done
	echo "MELTDOWN_BOT_RUNS${suffix} {\"runs\":$runs,\"completed\":$completed,\"rate\":0.5000,\"levels_flown\":$flown,\"levels_escaped\":$escaped$losses}"
}

# The loss fields as bot_run_losses.gd writes them.
# Usage: losses LEVEL_LIST DESTROYED TIMED_OUT NOT_FLOWN
losses() {
	echo ",\"lost_by_level\":$1,\"lost_by_outcome\":{\"destroyed\":$2,\"timed_out\":$3,\"not_flown\":$4}"
}

ship_line() {
	echo "MELTDOWN_BOT_SHIP {\"ship\":\"$1\",\"runs\":$2,\"finished\":$3,\"level1_escapes\":$4,\"level1_mean_hull\":65.36}"
}

# A shard's whole output, engine noise included: plain and fitted lines, then the
# two ship lines. Each ship is "RUNS COMPLETED FLOWN ESCAPED LEVEL1"; the
# optional fifth and sixth arguments are each ship's loss fields.
shard() {
	local file="$work/$1" first="$2" r c l e f
	local plain_losses="${5:-}" fitted_losses="${6:-}"
	read -r r c l e f <<< "$3"
	local fr fc fl fe ff
	read -r fr fc fl fe ff <<< "$4"
	{
		echo "WARNING: OpenXR: no runtime"
		ship_lines "" "$first" "$r" "$c" "$l" "$e" "$r" "$plain_losses"
		ship_lines "_FITTED" "$first" "$fr" "$fc" "$fl" "$fe" "$fr" "$fitted_losses"
		ship_line plain "$r" "$c" "$f"
		ship_line fitted "$fr" "$fc" "$ff"
	} > "$file"
	echo "$file"
}

a="$(shard a.txt 1 "13 7 40 34 10" "13 9 45 41 11" "$(losses "[4,2]" 4 1 1)")"
b="$(shard b.txt 14 "12 4 30 22 8" "12 6 38 32 10" "$(losses "[5,2,1]" 6 2 0)")"
expect_output "two shards add up per ship, losses by level and outcome under each" \
	"plain ship: 25 runs, 11 completed, rate 0.4400, 70 levels flown, 56 escaped, 18 level-1 escapes
  lost by level: 1: 9, 2: 4, 3: 1
  lost by outcome: 10 destroyed, 3 timed out, 1 could not be flown
maxed ship: 25 runs, 15 completed, rate 0.6000, 83 levels flown, 73 escaped, 21 level-1 escapes
  lost by level: 1: 10
  lost by outcome: 10 destroyed, 0 timed out, 0 could not be flown" \
	combine 25 "$a" "$b"
zero="$(shard zero.txt 1 "25 0 25 0 0" "25 0 25 0 0")"
expect_output "no completed run is reported, not judged" \
	"plain ship: 25 runs, 0 completed, rate 0.0000, 25 levels flown, 0 escaped, 0 level-1 escapes
  lost by level: 1: 25
  lost by outcome: 25 destroyed, 0 timed out, 0 could not be flown
maxed ship: 25 runs, 0 completed, rate 0.0000, 25 levels flown, 0 escaped, 0 level-1 escapes
  lost by level: 1: 25
  lost by outcome: 25 destroyed, 0 timed out, 0 could not be flown" \
	combine 25 "$zero"
all="$(shard all.txt 1 "13 13 52 52 13" "13 13 52 52 13" "$(losses "[]" 0 0 0)" "$(losses "[]" 0 0 0)")"
expect_output "no lost run says none" \
	"plain ship: 13 runs, 13 completed, rate 1.0000, 52 levels flown, 52 escaped, 13 level-1 escapes
  lost by level: none
  lost by outcome: 0 destroyed, 0 timed out, 0 could not be flown
maxed ship: 13 runs, 13 completed, rate 1.0000, 52 levels flown, 52 escaped, 13 level-1 escapes
  lost by level: none
  lost by outcome: 0 destroyed, 0 timed out, 0 could not be flown" \
	combine 13 "$all"

expect_refused "runs short of the request fail" combine 26 "$a" "$b"
expect_refused "a missing shard file fails" combine 25 "$a" "$work/absent.txt"
printf 'seed 3: RUNNING at tick 193: ship destroyed\n' > "$work/crashed.txt"
expect_refused "no summary line fails" combine 25 "$a" "$work/crashed.txt"

{
	ship_lines "" 1 13 7 40 34
	ship_line plain 13 7 10
} > "$work/plainonly.txt"
expect_refused "a shard without the maxed ship fails" combine 13 "$work/plainonly.txt"

{
	ship_lines "" 1 13 7 40 34
	ship_lines "_FITTED" 1 13 9 45 41
	ship_line plain 13 7 10
} > "$work/noshipline.txt"
expect_refused "a shard without the fitted ship line fails" combine 13 "$work/noshipline.txt"

{
	ship_lines "" 1 13 7 40 34 12
	ship_lines "_FITTED" 1 13 9 45 41
	ship_line plain 13 7 10
	ship_line fitted 13 9 11
} > "$work/unbuilt.txt"
expect_refused "a run seed that did not build fails" combine 13 "$work/unbuilt.txt"

twice="$(shard twice.txt 1 "13 7 40 34 10" "13 9 45 41 11")"
ship_lines "" 1 13 7 40 34 0 >> "$twice"
expect_refused "two summary lines fail" combine 13 "$twice"

{
	ship_lines "" 1 13 7 40 34
	ship_lines "_FITTED" 1 13 9 45 41
	ship_line plain 13 6 10
	ship_line fitted 13 9 11
} > "$work/mismatch.txt"
expect_refused "a ship line that disagrees with its summary fails" combine 13 "$work/mismatch.txt"

{
	echo 'MELTDOWN_BOT_RUNS {"runs":13,"completed":7,"lev'
	ship_lines "_FITTED" 1 13 9 45 41
	ship_line plain 13 7 10
	ship_line fitted 13 9 11
} > "$work/cut.txt"
expect_refused "a cut-off summary fails" combine 13 "$work/cut.txt"

{
	ship_lines "" 1 13 7 40 34 | sed 's/"completed":7/"completed":"7"/'
	ship_lines "_FITTED" 1 13 9 45 41
	ship_line plain 13 7 10
	ship_line fitted 13 9 11
} > "$work/text.txt"
expect_refused "a count written as text fails" combine 13 "$work/text.txt"

short="$(shard short.txt 1 "13 7 40 34 10" "13 9 45 41 11" "$(losses "[4,1]" 4 1 1)")"
expect_refused "losses by level short of the runs not completed fail" combine 13 "$short"
odd="$(shard odd.txt 1 "13 7 40 34 10" "13 9 45 41 11" "$(losses "[6]" 4 1 0)")"
expect_refused "losses by outcome short of the runs not completed fail" combine 13 "$odd"
old="$(shard old.txt 1 "13 7 40 34 10" "13 9 45 41 11" ",\"x\":0")"
expect_refused "a summary without the loss fields fails" combine 13 "$old"

more="$(shard more.txt 1 "13 14 40 34 10" "13 9 45 41 11")"
expect_refused "more completed than runs fails" combine 13 "$more"
expect_refused "runs not a number" combine 1e2 "$a"
expect_refused "no files" combine 25
expect_refused "unknown command" range 100 8 0

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "all bot run rate checks passed"
