extends RefCounted

## Where and how the run sweep's runs are lost (#1195, RUN-1, CRW-3, DEV-6):
## per ship, losses per level and per outcome, written after the older summary
## fields without changing them.

const RunSweep := preload("res://tests/bot_run_sweep.gd")
const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Losses := preload("res://tests/bot_run_losses.gd")


static func _flown(escaped: bool, outcome: String, destroyed: bool) -> EscapeSweep.SeedResult:
	var flown: EscapeSweep.SeedResult = EscapeSweep.SeedResult.new()
	flown.escaped = escaped
	flown.cleared = escaped
	flown.outcome = outcome
	flown.destroyed = destroyed
	return flown


## Run seed 1 (A) is destroyed on level 1; run seed 2 (B) escapes level 1 and
## times out on level 2 (the countdown ran out, ship whole).
static func _a_and_b() -> Callable:
	return func(run_seed: int, index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		if run_seed == 1:
			return _flown(false, "RUNNING", true)
		if index == 0:
			return _flown(true, "ESCAPED", false)
		return _flown(false, "LOST", false)


func test_a_lost_on_level_1_and_b_on_level_2_give_the_counts() -> String:
	var result: Dictionary = RunSweep.run(1, 2, _a_and_b())
	if not result["errors"].is_empty():
		return "errors: %s" % [result["errors"]]
	if result["lost_by_level"] != [1, 1]:
		return "lost_by_level %s, expected [1, 1]" % [result["lost_by_level"]]
	var expected: Dictionary = {"destroyed": 1, "timed_out": 1, "not_flown": 0}
	if result["lost_by_outcome"] != expected:
		return "lost_by_outcome %s, expected %s" % [result["lost_by_outcome"], expected]
	var line: String = RunSweep.summary(result)
	var tail: String = ',"lost_by_level":[1,1],"lost_by_outcome":{"destroyed":1,"timed_out":1,"not_flown":0}}'
	if not line.ends_with(tail):
		return "summary %s does not end with %s" % [line, tail]
	return ""


func test_older_summary_fields_keep_their_names_and_values() -> String:
	var result: Dictionary = RunSweep.run(1, 2, _a_and_b())
	var line: String = RunSweep.summary(result)
	var head: String = 'MELTDOWN_BOT_RUNS {"runs":2,"completed":0,"rate":0.0000,"levels_flown":3,"levels_escaped":1,'
	if not line.begins_with(head):
		return "summary %s does not start with %s" % [line, head]
	var parsed: Variant = JSON.parse_string(line.trim_prefix(RunSweep.SUMMARY_TAG + " "))
	if not parsed is Dictionary:
		return "summary is not JSON: %s" % line
	return ""


func test_fitted_summary_carries_the_loss_fields_too() -> String:
	var result: Dictionary = RunSweep.run(1, 2, _a_and_b(), null,
			RunSweep.RUN_TAG + RunSweep.FITTED_SUFFIX)
	var line: String = RunSweep.summary(result, RunSweep.SUMMARY_TAG + RunSweep.FITTED_SUFFIX)
	if not line.begins_with("MELTDOWN_BOT_RUNS_FITTED ") or not line.contains('"lost_by_level":[1,1]'):
		return "fitted summary %s" % line
	return ""


func test_no_loss_writes_an_empty_level_list() -> String:
	var stub: Callable = func(_run_seed: int, _index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		return _flown(true, "ESCAPED", false)
	var line: String = RunSweep.summary(RunSweep.run(1, 2, stub))
	if not line.ends_with(',"lost_by_level":[],"lost_by_outcome":{"destroyed":0,"timed_out":0,"not_flown":0}}'):
		return "summary %s" % line
	return ""


func test_a_level_that_could_not_be_flown_is_not_flown() -> String:
	for outcome: String in ["NO_LEVEL", "NO_REACTOR"]:
		if Losses.outcome_of(outcome, false) != Losses.NOT_FLOWN:
			return "%s counted as %s" % [outcome, Losses.outcome_of(outcome, false)]
	if Losses.outcome_of("RUNNING", false) != Losses.TIMED_OUT:
		return "still flying at the tick limit is not timed out"
	if Losses.outcome_of("LOST", true) != Losses.DESTROYED:
		return "a destroyed ship is not destroyed"
	return ""


func test_lost_counts_add_up_to_the_runs_not_completed() -> String:
	# Run seeds 1 to 6: even seeds escape every level, odd ones are destroyed on
	# level (seed + 1) / 2. Every run has at least three levels.
	var stub: Callable = func(run_seed: int, index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		var lose: bool = run_seed % 2 == 1 and index == (run_seed - 1) / 2
		return _flown(not lose, "LOST" if lose else "ESCAPED", lose)
	var result: Dictionary = RunSweep.run(1, 6, stub)
	var lost: int = 0
	for count: int in result["lost_by_level"]:
		lost += count
	var by_outcome: int = 0
	for outcome: String in Losses.OUTCOMES:
		by_outcome += result["lost_by_outcome"][outcome]
	var expected: int = int(result["runs"]) - int(result["completed"])
	if lost != expected or by_outcome != expected or result["lost_by_level"] != [1, 1, 1]:
		return "lost_by_level %s, outcomes %s, for %d runs not completed" % [
				result["lost_by_level"], result["lost_by_outcome"], expected]
	return ""
