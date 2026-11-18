extends RefCounted

## The bot pilot fights through generated levels with robots and debris
## (#492, GEN-3, DEV-6). Before #492 it cleared none of seeds 1..10 and 19 of
## seeds 1..300; every flight it lost ended with the ship destroyed before the
## reactor. The full 300-seed numbers are in the #492 pull request; this pins a
## short run so a change that makes the bot a worse fighter shows up in CI.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const FIRST_SEED: int = 1
const SEEDS: int = 10
## Cleared levels among seeds 1..10 with the #492 bot: 4 (seeds 1, 6, 8, 10).
## The pin leaves one seed of room so a harmless change elsewhere does not
## break it, and still fails if the bot falls back to clearing none.
const MIN_CLEARED: int = 3
const TIME_LIMIT_MS: int = 90000


func test_the_bot_clears_generated_levels_with_robots_and_debris() -> String:
	var result: Dictionary = Sweep.run(FIRST_SEED, SEEDS, true, true)
	print("  %s" % Sweep.summary(result))
	if result["cleared"] < MIN_CLEARED:
		return "cleared %d of seeds %d..%d, expected at least %d: %s" % [result["cleared"],
				FIRST_SEED, FIRST_SEED + SEEDS - 1, MIN_CLEARED, result["failures"]]
	if result["rate"] < Sweep.REQUIRED_RATE:
		return "escape rate %.4f over cleared levels, below %.2f: %s" % [result["rate"],
				Sweep.REQUIRED_RATE, result["failures"]]
	if result["ms"] > TIME_LIMIT_MS:
		return "the run took %d ms, over %d" % [result["ms"], TIME_LIMIT_MS]
	return ""
