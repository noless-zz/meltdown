extends RefCounted

## The run sweep builds each level as the game does after a shaft (#1173,
## RUN-1, GEN-2): level 1 at robot scale 1.0, every later level with the chosen
## shaft's `risk.robot_count`, through `RobotPlan.scaled`. The levels it builds
## for a run seed have the robot counts the game's `seed:<n>:robots=<scale>`
## source gives (`LevelSwitch.load_level`), and `--shaft=<index>` picks the
## offered shaft at that position.

const RunSweep := preload("res://tests/bot_run_sweep.gd")
const EscapeSweep := preload("res://tests/bot_escape_sweep.gd")
const Levels := preload("res://tests/bot_sweep_levels.gd")
## Takes deep, hot, deep, steady under the first-offered rule
## (`test_bot_run_sweep.gd`), so it flies three scaled levels.
const RUN_SEED: int = 12345


static func _escaped() -> EscapeSweep.SeedResult:
	var flown: EscapeSweep.SeedResult = EscapeSweep.SeedResult.new()
	flown.escaped = true
	flown.outcome = "ESCAPED"
	return flown


## A `fly_level` that escapes every level.
static func _stub() -> Callable:
	return func(_run_seed: int, _index: int, _level_seed: int,
			_robot_scale: float) -> EscapeSweep.SeedResult:
		return _escaped()


static func _shafts() -> ShaftOffer:
	return ShaftOffer.build(FileAccess.get_file_as_string(RunSweep.SHAFTS_FILE))


## [level seed, robot scale] for each level `RUN_SEED` flies with every level
## escaped, taking the offered shaft at `shaft_index`.
static func _levels_flown(shaft_index: int = 0) -> Array:
	var flown: Array = []
	var stub: Callable = func(_run_seed: int, _index: int, level_seed: int,
			robot_scale: float) -> EscapeSweep.SeedResult:
		flown.append([level_seed, robot_scale])
		return _escaped()
	RunSweep.fly_run(RUN_SEED, FileAccess.get_file_as_string(RunSweep.RUN_FILE), _shafts(),
			stub, shaft_index)
	return flown


func test_levels_after_the_first_take_the_chosen_shafts_robot_scale() -> String:
	var shafts: ShaftOffer = _shafts()
	var flown: RunSweep.RunResult = RunSweep.fly_run(RUN_SEED,
			FileAccess.get_file_as_string(RunSweep.RUN_FILE), shafts, _stub())
	if flown.scales.size() != flown.flown or flown.scales[0] != 1.0:
		return "scales %s for %d levels; level 1 must be 1.0" % [flown.scales, flown.flown]
	for index: int in range(1, flown.flown):
		var expected: float = float(shafts.risks[flown.shafts[index - 1]]["robot_count"])
		if flown.scales[index] != expected:
			return "level %d through %s built at %s, the shaft's robot_count is %s" % [index,
					flown.shafts[index - 1], flown.scales[index], expected]
	if not flown.line().contains('"robot_scales":[1.00,1.30,1.10,1.30,1.00]'):
		return "run line %s" % flown.line()
	return ""


func test_sweep_levels_have_the_games_robot_counts() -> String:
	var levels: Levels = Levels.new(true, true)
	if levels.broken() != "":
		return levels.broken()
	var scaled: int = 0
	for entry: Array in _levels_flown():
		var level_seed: int = entry[0]
		var robot_scale: float = entry[1]
		var swept: LevelDef = levels.level_of(levels.generate(level_seed), robot_scale)
		var source: String = LevelSwitch.seed_source(level_seed, robot_scale)
		var game: LevelDef = LevelSwitch.load_level(source)
		if swept.error != "" or game == null:
			return "%s: the sweep's level says \"%s\", the game's is %s" % [source, swept.error,
					"missing" if game == null else "built"]
		if swept.robots.spawns.size() != game.robots.spawns.size():
			return "%s: the sweep builds %d robots, the game %d" % [source,
					swept.robots.spawns.size(), game.robots.spawns.size()]
		if robot_scale != 1.0:
			scaled += 1
	if scaled == 0:
		return "run seed %d flew no scaled level" % RUN_SEED
	return ""


func test_shaft_index_takes_that_offered_shaft_or_the_last() -> String:
	var plan: RunPlan = RunPlan.build(RUN_SEED, FileAccess.get_file_as_string(RunSweep.RUN_FILE))
	var shafts: ShaftOffer = _shafts()
	for shaft_index: int in [1, 2, 7]:
		var flown: RunSweep.RunResult = RunSweep.fly_run(RUN_SEED,
				FileAccess.get_file_as_string(RunSweep.RUN_FILE), shafts, _stub(), shaft_index)
		var state: RunState = RunState.new(plan, shafts)
		for index: int in range(1, plan.level_count()):
			state.advance()
			var offered: Array[String] = state.offer()
			var expected: String = offered[mini(shaft_index, offered.size() - 1)]
			if flown.shafts[index - 1] != expected:
				return "--shaft=%d took %s into level %d, offered %s" % [shaft_index,
						flown.shafts[index - 1], index, offered]
			state.choose(expected)
	return ""


func test_shaft_option_parses() -> String:
	var plain: Dictionary = RunSweep.parse_options(PackedStringArray([]))
	if plain["error"] != "" or plain["shaft"] != 0:
		return "no options parsed as %s" % [plain]
	var second: Dictionary = RunSweep.parse_options(PackedStringArray(["--shaft=1", "--runs=5"]))
	if second["error"] != "" or second["shaft"] != 1 or second["runs"] != 5:
		return "--shaft=1 parsed as %s" % [second]
	for bad: String in ["--shaft=-1", "--shaft=deep", "--shaft="]:
		if RunSweep.parse_options(PackedStringArray([bad]))["error"] == "":
			return "%s was accepted" % bad
	return ""
