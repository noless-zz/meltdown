extends RefCounted

## The run sweep (#1009, RUN-1, RUN-7, GEN-2, gate G4): runs flown with a
## stubbed level result give the right summary; the same run seed twice gives
## the same `MELTDOWN_BOT_RUN` line, with the bot flying; the first offered
## shaft is taken, pinned for run seed 12345.

const RunSweep := preload("res://tests/bot_run_sweep.gd")
const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
## Run seed 12345's shafts under the first-offered rule, pinned.
const PINNED_SEED: int = 12345
const PINNED_SHAFTS: Array[String] = ["deep", "hot", "deep", "steady"]
## Run seed 12345 flown by the plain ship file, as printed before #1091 added
## the fitted ship: the plain report must not move (#1091). #1173 builds levels
## 2 and 3 with the deep and hot shafts' robot scales; the outcome did not move,
## the line gained `robot_scales`.
const PINNED_PLAIN_LINE: String = 'MELTDOWN_BOT_RUN {"seed":12345,"planned":5,"flown":3,"escaped":2,"ended":"LOST ship destroyed","robot_scales":[1.00,1.30,1.10]}'
const PINNED_PLAIN_SUMMARY: String = 'MELTDOWN_BOT_RUNS {"runs":1,"completed":0,"rate":0.0000,"levels_flown":3,"levels_escaped":2}'


static func _result(escaped: bool) -> EscapeSweep.SeedResult:
	var flown: EscapeSweep.SeedResult = EscapeSweep.SeedResult.new()
	flown.escaped = escaped
	flown.cleared = escaped
	flown.outcome = "ESCAPED" if escaped else "RUNNING"
	flown.destroyed = not escaped
	return flown


static func _plan(run_seed: int) -> RunPlan:
	return RunPlan.build(run_seed, FileAccess.get_file_as_string(RunSweep.RUN_FILE))


static func _shafts() -> ShaftOffer:
	return ShaftOffer.build(FileAccess.get_file_as_string(RunSweep.SHAFTS_FILE))


## The robot scales of the first `count` levels of `run_seed` under the
## first-offered rule, as a run line writes them (#1173).
static func _scales(run_seed: int, count: int) -> String:
	var state: RunState = RunState.new(_plan(run_seed), _shafts())
	var written: PackedStringArray = []
	for index: int in count:
		if state.needs_choice():
			state.choose(state.offer()[0])
		written.append("%.2f" % float(state.current_risk()["robot_count"]))
		state.advance()
	return ",".join(written)


func test_stubbed_runs_escaped_escaped_lost_give_the_summary() -> String:
	# Run seeds 1 and 2 escape every level; run seed 3 is lost on its first.
	var stub: Callable = func(run_seed: int, _index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		return _result(run_seed != 3)
	var result: Dictionary = RunSweep.run(1, 3, stub)
	if not result["errors"].is_empty():
		return "errors: %s" % [result["errors"]]
	var first: int = _plan(1).level_count()
	var second: int = _plan(2).level_count()
	var flown: int = first + second + 1
	var expected: String = 'MELTDOWN_BOT_RUNS {"runs":3,"completed":2,"rate":0.6667,"levels_flown":%d,"levels_escaped":%d}' \
			% [flown, first + second]
	if RunSweep.summary(result) != expected:
		return "summary %s, expected %s" % [RunSweep.summary(result), expected]
	var lines: Array[String] = [
		'MELTDOWN_BOT_RUN {"seed":1,"planned":%d,"flown":%d,"escaped":%d,"ended":"completed","robot_scales":[%s]}' \
				% [first, first, first, _scales(1, first)],
		'MELTDOWN_BOT_RUN {"seed":2,"planned":%d,"flown":%d,"escaped":%d,"ended":"completed","robot_scales":[%s]}' \
				% [second, second, second, _scales(2, second)],
		'MELTDOWN_BOT_RUN {"seed":3,"planned":%d,"flown":1,"escaped":0,"ended":"RUNNING ship destroyed","robot_scales":[1.00]}' \
				% _plan(3).level_count(),
	]
	if result["lines"] != lines:
		return "lines %s, expected %s" % [result["lines"], lines]
	return ""


func test_each_level_flown_is_the_runs_next_level() -> String:
	var seeds: Array[int] = []
	var indices: Array[int] = []
	var stub: Callable = func(_run_seed: int, index: int, level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		indices.append(index)
		seeds.append(level_seed)
		return _result(true)
	var flown: RunSweep.RunResult = RunSweep.fly_run(PINNED_SEED,
			FileAccess.get_file_as_string(RunSweep.RUN_FILE), _shafts(), stub)
	var plan: RunPlan = _plan(PINNED_SEED)
	if not flown.completed() or flown.flown != plan.level_count():
		return "flew %d of %d levels, ended %s" % [flown.flown, plan.level_count(), flown.ended]
	var state: RunState = RunState.new(plan, _shafts())
	for index: int in plan.level_count():
		if state.needs_choice():
			state.choose(state.offer()[0])
		if indices[index] != index or seeds[index] != state.current_level_seed():
			return "level %d flew seed %d, the run's is %d" % [index, seeds[index], state.current_level_seed()]
		state.advance()
	return ""


func test_first_offered_shaft_is_taken_pinned_for_12345() -> String:
	var stub: Callable = func(_run_seed: int, _index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		return _result(true)
	var plan: RunPlan = _plan(PINNED_SEED)
	var shafts: ShaftOffer = _shafts()
	var flown: RunSweep.RunResult = RunSweep.fly_run(PINNED_SEED,
			FileAccess.get_file_as_string(RunSweep.RUN_FILE), shafts, stub)
	for index: int in range(1, plan.level_count()):
		var first: String = plan.offer_after(index - 1, shafts)[0]
		if flown.shafts[index - 1] != first:
			return "level %d took %s, the first offered is %s" % [index, flown.shafts[index - 1], first]
	if flown.shafts != PINNED_SHAFTS:
		return "run seed %d took %s, pinned %s" % [PINNED_SEED, flown.shafts, PINNED_SHAFTS]
	return ""


func test_same_run_seed_twice_gives_the_same_line() -> String:
	var first: Dictionary = RunSweep.run(PINNED_SEED, 1)
	var second: Dictionary = RunSweep.run(PINNED_SEED, 1)
	if not first["errors"].is_empty():
		return "errors: %s" % [first["errors"]]
	if first["lines"].size() != 1 or first["lines"] != second["lines"]:
		return "lines %s then %s" % [first["lines"], second["lines"]]
	if first["lines"][0] != PINNED_PLAIN_LINE or RunSweep.summary(first) != PINNED_PLAIN_SUMMARY:
		return "plain report %s %s, pinned %s %s" % [first["lines"][0], RunSweep.summary(first),
				PINNED_PLAIN_LINE, PINNED_PLAIN_SUMMARY]
	print("  bot run sweep: %s" % first["lines"][0])
	return ""


func test_broken_run_file_is_an_error() -> String:
	var stub: Callable = func(_run_seed: int, _index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		return _result(true)
	var flown: RunSweep.RunResult = RunSweep.fly_run(1, "{}", _shafts(), stub)
	if not flown.error.contains("run.json") or flown.flown != 0:
		return "a broken run file gave error \"%s\" after %d levels" % [flown.error, flown.flown]
	return ""
