extends RefCounted

## The bot pilot fights through generated levels with robots and debris
## (#492, GEN-3, DEV-6). Before #492 it cleared none of seeds 1..10 and 19 of
## seeds 1..300; every flight it lost ended with the ship destroyed before the
## reactor. The full 300-seed numbers are in the #492 pull request; this pins a
## short run so a change that makes the bot a worse fighter shows up in CI.
##
## Since #612 robots wind up before they fire, and seeds 1 and 4 stalled at a
## corner until the 36,000-tick limit, which took about 45 of the test's 70 s
## and pushed CI over 90 s (#658). `BotStall` gets the bot through; no seed
## here may run out of ticks again, so a stall shows up as a failure, not as
## a slow test. Seeds 1..10 now take about 30 s on a desktop.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const FIRST_SEED: int = 1
const SEEDS: int = 10
## Cleared levels among seeds 1..10: 4 with the #492 bot (seeds 1, 6, 8, 10),
## 8 after #612, all 10 with the #658 stall check. The pin leaves two seeds of
## room so a harmless change elsewhere does not break it, and still fails if
## the bot falls back to clearing few.
const MIN_CLEARED: int = 8
const TIME_LIMIT_MS: int = 90000


func test_the_bot_clears_generated_levels_with_robots_and_debris() -> String:
	var result: Dictionary = Sweep.run(FIRST_SEED, SEEDS, true, true)
	print("  %s" % Sweep.summary(result))
	if result["cleared"] < MIN_CLEARED:
		return "cleared %d of seeds %d..%d, expected at least %d: %s" % [result["cleared"],
				FIRST_SEED, FIRST_SEED + SEEDS - 1, MIN_CLEARED, result["failures"]]
	if result["timed_out"] > 0:
		return "%d of seeds %d..%d ran out of ticks: %s" % [result["timed_out"], FIRST_SEED,
				FIRST_SEED + SEEDS - 1, result["failures"]]
	if result["rate"] < Sweep.REQUIRED_RATE:
		return "escape rate %.4f over cleared levels, below %.2f: %s" % [result["rate"],
				Sweep.REQUIRED_RATE, result["failures"]]
	if result["ms"] > TIME_LIMIT_MS:
		return "the run took %d ms, over %d" % [result["ms"], TIME_LIMIT_MS]
	return ""
