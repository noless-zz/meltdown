#!/usr/bin/env bash
# Checks tools/bot_escape_rate.sh on made-up sweep output, so a broken shard split
# or summary parser fails before the nightly job spends its time flying (#461).
# The nightly workflow runs this first; it needs only bash and jq.
# Usage: tools/test_bot_escape_rate.sh
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bot_escape_rate.sh"
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

# A shard's output as the sweep prints it, failure lines and engine noise included.
shard() {
	local file="$work/$1" json="$2"
	{
		echo "WARNING: OpenXR: no runtime"
		echo "seed 3: RUNNING at tick 193: ship destroyed"
		echo "bot escape sweep: 0 without a reactor, 1 not escaped, 1000 ms"
		echo "MELTDOWN_BOT_ESCAPE $json"
	} > "$file"
	echo "$file"
}

line() {
	local seeds="$1" cleared="$2" escaped="$3"
	echo "{\"seeds\":$seeds,\"cleared\":$cleared,\"escaped\":$escaped,\"looped\":0,\"rate\":1.0000,\"robots_destroyed\":4,\"robots\":true,\"debris\":true}"
}

# Shard ranges cover 1..SEEDS once, in order.
expect_output "first of 8 shards over 1000" "1 125" range 1000 8 0
expect_output "last of 8 shards over 1000" "876 125" range 1000 8 7
expect_output "uneven split, short last shard" "10 1" range 10 4 3
expect_output "shard past the end flies nothing" "4 0" range 3 8 3
expect_output "one shard takes everything" "1 1000" range 1000 1 0
covered=0
for index in 0 1 2 3 4 5 6; do
	read -r first count <<< "$("$script" range 1001 7 "$index")"
	[ "$first" -eq $((covered + 1)) ] || [ "$count" -eq 0 ] || {
		echo "FAIL shard $index of 1001 starts at $first after $covered" >&2
		failures=$((failures + 1))
	}
	covered=$((covered + count))
done
if [ "$covered" -eq 1001 ]; then
	echo "ok   seven shards cover 1001 seeds"
else
	echo "FAIL seven shards cover $covered of 1001 seeds" >&2
	failures=$((failures + 1))
fi
expect_refused "zero seeds" range 0 8 0
expect_refused "index past the shards" range 1000 8 8
expect_refused "seeds not a number" range "10e3" 8 0

a="$(shard a.txt "$(line 500 30 29)")"
b="$(shard b.txt "$(line 500 10 10)")"
expect_output "two shards add up" \
	"bot escape rate: 39 escaped of 40 cleared = 0.9750 over 1000 seeds (robots, debris)" \
	combine 1000 "$a" "$b"
exact="$(shard exact.txt "$(line 1000 20 19)")"
expect_output "exactly 0.95 passes" \
	"bot escape rate: 19 escaped of 20 cleared = 0.9500 over 1000 seeds (robots, debris)" \
	combine 1000 "$exact"

low="$(shard low.txt "$(line 500 20 18)")"
expect_refused "below 0.95 fails" combine 1000 "$a" "$low"
none="$(shard none.txt "$(line 1000 0 0)")"
expect_refused "nothing cleared fails" combine 1000 "$none"
expect_refused "seeds short of the request fail" combine 1000 "$a"
expect_refused "a missing shard file fails" combine 1000 "$a" "$work/absent.txt"

printf 'seed 3: RUNNING at tick 193: ship destroyed\n' > "$work/crashed.txt"
expect_refused "no summary line fails" combine 1000 "$a" "$work/crashed.txt"
twice="$(shard twice.txt "$(line 500 10 10)")"
echo "MELTDOWN_BOT_ESCAPE $(line 500 10 10)" >> "$twice"
expect_refused "two summary lines fail" combine 1000 "$a" "$twice"
cut="$(shard cut.txt '{"seeds":500,"cleared":10,"esc')"
expect_refused "a cut-off line fails" combine 1000 "$a" "$cut"
text="$(shard text.txt '{"seeds":500,"cleared":"10","escaped":10,"robots":true,"debris":true}')"
expect_refused "a count written as text fails" combine 1000 "$a" "$text"
bare="$(shard bare.txt '{"seeds":500,"cleared":10,"escaped":10,"looped":0,"rate":1.0000}')"
expect_refused "a run without robots or debris fails" combine 1000 "$a" "$bare"
nodebris="$(shard nodebris.txt '{"seeds":500,"cleared":10,"escaped":10,"robots":true}')"
expect_refused "a run without debris fails" combine 1000 "$a" "$nodebris"
more="$(shard more.txt "$(line 500 10 11)")"
expect_refused "more escaped than cleared fails" combine 1000 "$a" "$more"
expect_refused "no files" combine 1000
expect_refused "unknown command" average 1000

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed" >&2
	exit 1
fi
echo "all bot escape rate checks passed"
