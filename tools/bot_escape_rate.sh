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
#       ticks, R without a reactor; lost under 10 s A, 10 to 60 s B, over 60 s C,
#       median M robots awake)" (#495, #534), where R is what is left of N and M
#       is taken over every shard's MELTDOWN_BOT_LOST lines ("none" when nothing
#       was lost), then a
#       GitHub ::warning:: line when fewer than 100 levels were cleared, since the
#       rate then rests on a small sample. Only escaped over cleared is judged.
#       Exits 1 when a file has no summary line, more than one, one that does not
#       parse, one from a run without robots or debris, one whose loss buckets or
#       MELTDOWN_BOT_LOST lines do not match its lost count, when the seeds do not add
#       up to SEEDS, when nothing was cleared, or when the rate is below 0.95.
#
# Needs bash and jq. Kept apart from the workflow so tools/test_bot_escape_rate.sh
# can check the parsing without Godot.
set -euo pipefail

tag="MELTDOWN_BOT_ESCAPE"
lost_tag="MELTDOWN_BOT_LOST"
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

# Prints "SEEDS CLEARED ESCAPED LOST TIMED_OUT UNDER_10 TO_60 OVER_60" from one
# sweep output file.
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
			and (.lost_under_10_s | type) == "number" and (.lost_10_to_60_s | type) == "number"
			and (.lost_over_60_s | type) == "number"
			and .lost_under_10_s >= 0 and .lost_10_to_60_s >= 0 and .lost_over_60_s >= 0
			and .lost_under_10_s + .lost_10_to_60_s + .lost_over_60_s == .lost_before_reactor
			and ((.lost_awake_median | type) == "number" or .lost_awake_median == null)
		then "\(.seeds) \(.cleared) \(.escaped) \(.lost_before_reactor) \(.timed_out) \(.lost_under_10_s) \(.lost_10_to_60_s) \(.lost_over_60_s)"
		else error("not a robots and debris sweep") end' <<< "$json" 2> /dev/null \
		|| fail "$file: the ${tag} line does not parse as a robots and debris sweep: $json"
}

# Prints the awake count of every MELTDOWN_BOT_LOST line in one file, one per line.
read_awake() {
	local file="$1" json
	{ grep "^${lost_tag} " "$file" || true; } | while IFS= read -r json; do
		jq -er 'if (.seed | type) == "number" and (.awake | type) == "number"
				and .awake >= 0 and .awake == (.awake | floor)
			then .awake else error("bad") end' <<< "${json#"${lost_tag} "}" 2> /dev/null \
			|| { echo "$file: a ${lost_tag} line does not parse: $json" >&2; echo "x"; }
	done
}

# The median of the whole numbers on standard input, to one place, or "none".
median() {
	sort -n | awk '{ v[NR] = $1 } END {
		if (NR == 0) { print "none"; exit }
		if (NR % 2) printf "%.1f\n", v[(NR + 1) / 2]
		else printf "%.1f\n", (v[NR / 2] + v[NR / 2 + 1]) / 2
	}'
}

combine() {
	local expected="$1"
	shift
	is_count "$expected" && [ "$expected" -ge 1 ] || fail "seeds must be a positive whole number, got '$expected'"
	[ "$#" -ge 1 ] || fail "no shard output files"
	local seeds=0 cleared=0 escaped=0 lost=0 timed_out=0 under=0 middle=0 over=0
	local file values s c e l t u m o awake="" shard_awake count
	for file in "$@"; do
		values="$(read_summary "$file")"
		read -r s c e l t u m o <<< "$values"
		shard_awake="$(read_awake "$file")"
		! grep -qx "x" <<< "$shard_awake" || fail "$file: a ${lost_tag} line does not parse"
		count="$(grep -c . <<< "$shard_awake" || true)"
		[ "$count" -eq "$l" ] || fail "$file: $count ${lost_tag} lines for $l seeds lost before the reactor"
		[ -z "$shard_awake" ] || awake+="$shard_awake"$'\n'
		under=$((under + u))
		middle=$((middle + m))
		over=$((over + o))
		seeds=$((seeds + s))
		cleared=$((cleared + c))
		escaped=$((escaped + e))
		lost=$((lost + l))
		timed_out=$((timed_out + t))
	done
	[ "$seeds" -eq "$expected" ] || fail "the shards flew $seeds seeds, expected $expected"
	local awake_median
	awake_median="$(printf '%s' "$awake" | grep . | median || true)"
	[ -n "$awake_median" ] || awake_median="none"
	local clear_line="bot clear rate: $cleared cleared of $seeds seeds ($lost lost before the reactor, $timed_out out of ticks, $((seeds - cleared - lost - timed_out)) without a reactor; lost under 10 s $under, 10 to 60 s $middle, over 60 s $over, median $awake_median robots awake)"
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
