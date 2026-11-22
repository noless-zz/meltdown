#!/usr/bin/env bash
# The nightly bot run sweep (#1174, gate G4 "bots complete full runs", RUN-1,
# CRW-3, DEV-6): .github/workflows/nightly-seeds.yml splits the run seeds over
# shards, each flying tests/bot_run_sweep.gd with the plain ship and the maxed
# ship (--profile / --fitting, #1091), and this script adds the shards up.
# The shard split itself is tools/bot_escape_rate.sh range.
#
#   tools/bot_run_rate.sh combine RUNS FILE...
#       Reads each shard's sweep output and prints one line per ship:
#       "plain ship: N runs, C completed, rate R, L levels flown, E escaped, F level-1 escapes"
#       "maxed ship: ..." (the sweep's _FITTED lines).
#       Under each ship's line (#1195), where its lost runs ended:
#       "  lost by level: 1: A, 2: B, ..." (or "none")
#       "  lost by outcome: D destroyed, T timed out, N could not be flown"
#       from the summary's lost_by_level and lost_by_outcome, added up over the
#       shards (a shard's level list can be shorter than another's).
#       The owner set no completion bar (Status #1, 22 Nov), so the rate is
#       reported and never judged. Exits 1 only when the output cannot be
#       trusted: a file without exactly one summary line per ship and one
#       MELTDOWN_BOT_SHIP line per ship, a line that does not parse, a summary
#       whose runs do not match its MELTDOWN_BOT_RUN lines (a run seed that
#       failed to build prints none), loss counts that do not add up to the
#       runs not completed, or runs that do not add up to RUNS.
#
# Needs bash and jq. Kept apart from the workflow so tools/test_bot_run_rate.sh
# can check the parsing without Godot.
set -euo pipefail

run_tag="MELTDOWN_BOT_RUN"
summary_tag="MELTDOWN_BOT_RUNS"
ship_tag="MELTDOWN_BOT_SHIP"
fitted="_FITTED"

fail() {
	echo "$*" >&2
	exit 1
}

is_count() {
	[[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

# The one line of FILE starting with TAG and a space, without the tag.
one_line() {
	local file="$1" tag="$2" lines
	lines="$(grep -c "^${tag} " "$file" || true)"
	[ "$lines" -eq 1 ] || fail "$file: expected one ${tag} line, found $lines"
	sed -n "s/^${tag} //p" "$file"
}

# Prints "RUNS COMPLETED LEVELS_FLOWN LEVELS_ESCAPED LEVEL1_ESCAPES DESTROYED
# TIMED_OUT NOT_FLOWN LOST_BY_LEVEL" for one ship of one file, LOST_BY_LEVEL
# comma separated ("-" when nothing was lost). SUFFIX is "" for the plain ship and _FITTED for the maxed one;
# SHIP is the name its MELTDOWN_BOT_SHIP line carries.
read_ship() {
	local file="$1" suffix="$2" ship="$3" summary ship_json values runs lines
	summary="$(one_line "$file" "${summary_tag}${suffix}")"
	values="$(jq -er '
		def count: type == "number" and . >= 0 and . == floor;
		if (.runs | count) and .runs >= 1 and (.completed | count) and (.levels_flown | count)
			and (.levels_escaped | count) and .completed <= .runs
			and .levels_escaped <= .levels_flown and .levels_flown >= .runs
		then "\(.runs) \(.completed) \(.levels_flown) \(.levels_escaped)"
		else error("bad") end' <<< "$summary" 2> /dev/null)" \
		|| fail "$file: the ${summary_tag}${suffix} line does not parse: $summary"
	ship_json="$({ grep "^${ship_tag} " "$file" || true; } \
		| sed "s/^${ship_tag} //" | jq -c --arg ship "$ship" 'select(.ship == $ship)' 2> /dev/null || true)"
	[ "$(grep -c . <<< "$ship_json" || true)" -eq 1 ] \
		|| fail "$file: expected one ${ship_tag} line for the $ship ship"
	read -r runs _ <<< "$values"
	local level1
	level1="$(jq -er --argjson runs "$runs" --argjson completed "$(cut -d' ' -f2 <<< "$values")" '
		if .runs == $runs and .finished == $completed and (.level1_escapes | type) == "number"
			and .level1_escapes >= 0 and .level1_escapes == (.level1_escapes | floor)
			and .level1_escapes <= .runs
		then .level1_escapes else error("bad") end' <<< "$ship_json" 2> /dev/null)" \
		|| fail "$file: the $ship ${ship_tag} line does not match its summary: $ship_json"
	lines="$(grep -c "^${run_tag}${suffix} " "$file" || true)"
	[ "$lines" -eq "$runs" ] \
		|| fail "$file: $lines ${run_tag}${suffix} lines for $runs runs: a run seed did not build"
	local losses
	losses="$(jq -er '
		def count: type == "number" and . >= 0 and . == floor;
		(.runs - .completed) as $lost
		| if (.lost_by_level | type) == "array" and all(.lost_by_level[]; count)
			and (.lost_by_level | add // 0) == $lost
			and (.lost_by_outcome | type) == "object"
			and (.lost_by_outcome | keys) == ["destroyed", "not_flown", "timed_out"]
			and all(.lost_by_outcome[]; count)
			and (.lost_by_outcome | add) == $lost
		then "\(.lost_by_outcome.destroyed) \(.lost_by_outcome.timed_out) \(.lost_by_outcome.not_flown) \(if .lost_by_level == [] then "-" else (.lost_by_level | map(tostring) | join(",")) end)"
		else error("bad") end' <<< "$summary" 2> /dev/null)" \
		|| fail "$file: the ${summary_tag}${suffix} loss counts do not add up to its runs not completed: $summary"
	echo "$values $level1 $losses"
}

# Adds two comma separated count lists position by position; "-" is empty.
add_levels() {
	local left="$1" right="$2"
	[ "$left" == "-" ] && left=""
	[ "$right" == "-" ] && right=""
	jq -nr --arg a "$left" --arg b "$right" '
		def list($s): if $s == "" then [] else $s | split(",") | map(tonumber) end;
		list($a) as $x | list($b) as $y
		| [range(0; [($x | length), ($y | length)] | max) | ($x[.] // 0) + ($y[.] // 0)]
		| if . == [] then "-" else map(tostring) | join(",") end'
}

combine() {
	local expected="$1"
	shift
	is_count "$expected" && [ "$expected" -ge 1 ] || fail "runs must be a positive whole number, got '$expected'"
	[ "$#" -ge 1 ] || fail "no shard output files"
	local file
	for file in "$@"; do
		[ -f "$file" ] || fail "$file: missing"
	done
	local name suffix ship values r c l e f d t n v runs completed flown escaped first rate
	local destroyed timed_out not_flown by_level
	for name in plain maxed; do
		suffix=""
		ship="plain"
		if [ "$name" == "maxed" ]; then
			suffix="$fitted"
			ship="fitted"
		fi
		runs=0 completed=0 flown=0 escaped=0 first=0
		destroyed=0 timed_out=0 not_flown=0 by_level="-"
		for file in "$@"; do
			# An assignment, so a failed read stops the script under set -e.
			values="$(read_ship "$file" "$suffix" "$ship")"
			read -r r c l e f d t n v <<< "$values"
			runs=$((runs + r))
			completed=$((completed + c))
			flown=$((flown + l))
			escaped=$((escaped + e))
			first=$((first + f))
			destroyed=$((destroyed + d))
			timed_out=$((timed_out + t))
			not_flown=$((not_flown + n))
			by_level="$(add_levels "$by_level" "$v")"
		done
		[ "$runs" -eq "$expected" ] || fail "the shards flew $runs $name runs, expected $expected"
		rate="$(awk -v c="$completed" -v n="$runs" 'BEGIN { printf "%.4f", c / n }')"
		echo "$name ship: $runs runs, $completed completed, rate $rate, $flown levels flown, $escaped escaped, $first level-1 escapes"
		if [ "$by_level" == "-" ]; then
			echo "  lost by level: none"
		else
			echo "  lost by level: $(awk -F, '{ for (i = 1; i <= NF; i++) printf "%s%d: %d", (i > 1 ? ", " : ""), i, $i }' <<< "$by_level")"
		fi
		echo "  lost by outcome: $destroyed destroyed, $timed_out timed out, $not_flown could not be flown"
	done
}

case "${1:-}" in
	combine)
		[ "$#" -ge 2 ] || fail "usage: $0 combine RUNS FILE..."
		shift
		combine "$@"
		;;
	*)
		fail "usage: $0 combine RUNS FILE..."
		;;
esac
