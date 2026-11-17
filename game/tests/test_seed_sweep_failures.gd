extends RefCounted

## How many failure messages the seed sweep keeps (#358): the first ten by
## default, every one when asked with 0, so the nightly job's summary can list
## every failing seed. Two-module levels fail the reactor check on every seed.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 12


func _seeds_named(failures: Array) -> Array[int]:
	var named: Array[int] = []
	for message: String in failures:
		var level_seed: int = message.get_slice(":", 0).trim_prefix("seed ").to_int()
		if not named.has(level_seed):
			named.append(level_seed)
	return named


func test_the_default_keeps_the_first_ten_messages() -> String:
	var result: Dictionary = SeedSweep.run(1, SEEDS, 2)
	if result["failed"] != SEEDS:
		return "expected %d failing seeds: %s" % [SEEDS, SeedSweep.summary(result)]
	var kept: int = (result["failures"] as Array).size()
	return "" if kept == SeedSweep.KEPT_FAILURES else "kept %d messages, expected %d" % [kept, SeedSweep.KEPT_FAILURES]


func test_zero_keeps_a_message_for_every_failing_seed() -> String:
	var result: Dictionary = SeedSweep.run(1, SEEDS, 2, 0)
	if result["failed"] != SEEDS:
		return "expected %d failing seeds: %s" % [SEEDS, SeedSweep.summary(result)]
	var named: Array[int] = _seeds_named(result["failures"])
	var expected: Array[int] = []
	for level_seed: int in range(1, SEEDS + 1):
		expected.append(level_seed)
	return "" if named == expected else "messages name seeds %s, expected %s" % [named, expected]


func test_a_passing_sweep_keeps_no_messages_either_way() -> String:
	var result: Dictionary = SeedSweep.run(1, 5, SeedSweep.MODULE_COUNT, 0)
	if result["failed"] != 0:
		return "expected the default levels to pass: %s" % SeedSweep.summary(result)
	return "" if (result["failures"] as Array).is_empty() else "kept %s" % [result["failures"]]
