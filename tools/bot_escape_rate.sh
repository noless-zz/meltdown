#!/usr/bin/env bash
# The nightly bot escape sweep (#461, gate G3, DEV-6): 1,000 seeds with robots
# and debris do not fit one job comfortably, so .github/workflows/nightly-seeds.yml
# splits them over shards and this script does the arithmetic on both ends.
#
#   tools/bot_escape_rate.sh range SEEDS SHARDS INDEX
#       Prints "FIRST COUNT" for shard INDEX (0-based) of SHARDS over seeds
#       1..SEEDS. COUNT is 0 for a shard with nothing left to fly.
#   tools/bot_escape_rate.sh combine SEEDS FILE...
#       Reads each shard's sweep output, adds the counts and prints two lines:
#       "bot escape rate: E escaped of C cleared = R over N seeds (robots, debris)"
#       "bot clear rate: C cleared of N seeds (L lost before the reactor, T out of
#       ticks, R without a reactor)" (#495), where R is what is left of N, then a
#       GitHub ::warning:: line when fewer than 100 levels were cleared, since the
#       rate then rests on a small sample. Only escaped over cleared is judged.
#       Exits 1 when a file has no summary line, more than one, one that does not
#       parse, one from a run without robots or debris, when the seeds do not add
#       up to SEEDS, when nothing was cleared, or when the rate is below 0.95.
#
# Needs bash and jq. Kept apart from the workflow so tools/test_bot_escape_rate.sh
# can check the parsing without Godot.
set -euo pipefail

tag="MELTDOWN_BOT_ESCAPE"
# G3's bar, as REQUIRED_RATE in game/tests/bot_escape_sweep.gd, in hundredths so
# the comparison stays in whole numbers.
required_hundredths=95
# Fewer cleared levels than this and a single escape moves the rate by over a
# point, so the summary warns; it does not fail, the bar stays escaped/cleared.
small_sample=100

fail() {
	echo "$*" >&2
	exit 1
}

is_count() {
	[[ "$1" =~ ^(0|[1-9][0-9]*)$ ]]
}

range() {
	local seeds="$1" shards="$2" index="$3"
	is_count "$seeds" && [ "$seeds" -ge 1 ] || fail "seeds must be a positive whole number, got '$seeds'"
	is_count "$shards" && [ "$shards" -ge 1 ] || fail "shards must be a positive whole number, got '$shards'"
	is_count "$index" && [ "$index" -lt "$shards" ] || fail "index must be 0 to $((shards - 1)), got '$index'"
	local per=$(((seeds + shards - 1) / shards))
	local first=$((1 + index * per))
	local count=$((seeds - index * per))
	if [ "$count" -gt "$per" ]; then
		count="$per"
	elif [ "$count" -lt 0 ]; then
		count=0
	fi
	echo "$first $count"
}

# Prints "SEEDS CLEARED ESCAPED LOST TIMED_OUT" from one sweep output file.
read_summary() {
	local file="$1" lines json
	[ -f "$file" ] || fail "$file: missing"
	lines="$(grep -c "^${tag} " "$file" || true)"
	[ "$lines" -eq 1 ] || fail "$file: expected one ${tag} line, found $lines"
	json="$(sed -n "s/^${tag} //p" "$file")"
	# Type checks so a truncated or reworded line fails rather than reading as 0.
	jq -er '
		if (.seeds | type) == "number" and (.cleared | type) == "number"
			and (.escaped | type) == "number" and .robots == true and .debris == true
			and (.lost_before_reactor | type) == "number" and (.timed_out | type) == "number"
			and .seeds >= 0 and .cleared >= 0 and .escaped >= 0 and .escaped <= .cleared
			and .lost_before_reactor >= 0 and .timed_out >= 0
			and .cleared + .lost_before_reactor + .timed_out <= .seeds
		then "\(.seeds) \(.cleared) \(.escaped) \(.lost_before_reactor) \(.timed_out)"
		else error("not a robots and debris sweep") end' <<< "$json" 2> /dev/null \
		|| fail "$file: the ${tag} line does not parse as a robots and debris sweep: $json"
}

combine() {
	local expected="$1"
	shift
	is_count "$expected" && [ "$expected" -ge 1 ] || fail "seeds must be a positive whole number, got '$expected'"
	[ "$#" -ge 1 ] || fail "no shard output files"
	local seeds=0 cleared=0 escaped=0 lost=0 timed_out=0 file values s c e l t
	for file in "$@"; do
		values="$(read_summary "$file")"
		read -r s c e l t <<< "$values"
		seeds=$((seeds + s))
		cleared=$((cleared + c))
		escaped=$((escaped + e))
		lost=$((lost + l))
		timed_out=$((timed_out + t))
	done
	[ "$seeds" -eq "$expected" ] || fail "the shards flew $seeds seeds, expected $expected"
	local clear_line="bot clear rate: $cleared cleared of $seeds seeds ($lost lost before the reactor, $timed_out out of ticks, $((seeds - cleared - lost - timed_out)) without a reactor)"
	if [ "$cleared" -lt 1 ]; then
		echo "$clear_line"
		fail "bot escape rate: no level cleared in $seeds seeds"
	fi
	local rate
	rate="$(awk -v e="$escaped" -v c="$cleared" 'BEGIN { printf "%.4f", e / c }')"
	echo "bot escape rate: $escaped escaped of $cleared cleared = $rate over $seeds seeds (robots, debris)"
	echo "$clear_line"
	if [ "$cleared" -lt "$small_sample" ]; then
		echo "::warning::the G3 bot escape rate rests on a small sample: $cleared levels cleared, fewer than $small_sample"
	fi
	[ $((escaped * 100)) -ge $((cleared * required_hundredths)) ] \
		|| fail "the rate $rate is below 0.$required_hundredths"
}

case "${1:-}" in
	range)
		[ "$#" -eq 4 ] || fail "usage: $0 range SEEDS SHARDS INDEX"
		range "$2" "$3" "$4"
		;;
	combine)
		[ "$#" -ge 2 ] || fail "usage: $0 combine SEEDS FILE..."
		shift
		combine "$@"
		;;
	*)
		fail "usage: $0 range SEEDS SHARDS INDEX | combine SEEDS FILE..."
		;;
esac
