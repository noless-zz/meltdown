extends RefCounted

## Generated levels place trapped miners from a data file (#938, SLV-3, CRW-1,
## GEN-1, GEN-2, GEN-3, ARC-2, ARC-4): the file is read key by key, each miner
## keeps the file's distances in a module box the start reaches, the same seed
## gives the same miners, the miners change neither the reactor, the robots
## nor the debris, and a plan that cannot fit its miners places fewer with a
## note instead of failing.

const SEEDS: int = 200
const PINNED_SEEDS: Array[int] = [0, 17, 512]
const VALID: Dictionary = {"count": [1, 3], "min_start_distance": 10,
		"min_reactor_distance": 5, "min_robot_distance": 3}

var _inputs: SeedLevel = SeedLevel.load_inputs()


func _rejects(data: Dictionary, name: String) -> String:
	var plan: MinerPlan = MinerPlan.parse_json(JSON.stringify(data))
	if plan.error == "":
		return "%s accepted" % JSON.stringify(data)
	if not plan.error.contains(name):
		return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


## The level for `level_seed` with the shipped inputs and `plan` for miners.
func _level(level_seed: int, plan: MinerPlan) -> LevelDef:
	var generator: MineGenerator = _inputs.generate(level_seed)
	return generator.to_level_def(_inputs.reactor_plan, _inputs.tuning.radius,
			_inputs.robot_plan, _inputs.debris_plan, plan)


func test_shipped_file_reads() -> String:
	if _inputs.error != "":
		return _inputs.error
	var plan: MinerPlan = _inputs.miner_plan
	if plan.min_count != 0 or plan.max_count != 2:
		return "count %d..%d, expected 0..2" % [plan.min_count, plan.max_count]
	var parsed: MinerPlan = MinerPlan.parse_json(JSON.stringify(VALID))
	if parsed.error != "" or parsed.min_count != 1 or parsed.max_count != 3 \
			or parsed.min_start_distance_mm != 10000 or parsed.min_reactor_distance_mm != 5000 \
			or parsed.min_robot_distance_mm != 3000:
		return "VALID read as \"%s\", count %d..%d, distances %d, %d and %d mm" % [parsed.error,
				parsed.min_count, parsed.max_count, parsed.min_start_distance_mm,
				parsed.min_reactor_distance_mm, parsed.min_robot_distance_mm]
	return ""


func test_file_is_rejected_naming_the_bad_key() -> String:
	var cases: Array = [
		["count", 2, "count"], ["count", [2], "count"], ["count", [0.5, 2], "count"],
		["count", [3, 1], "count"], ["count", [-1, 2], "count"],
		["min_start_distance", -1, "min_start_distance"],
		["min_reactor_distance", "far", "min_reactor_distance"],
		["min_robot_distance", 99999, "min_robot_distance"],
	]
	for case: Array in cases:
		var data: Dictionary = VALID.duplicate()
		data[case[0]] = case[1]
		var problem: String = _rejects(data, case[2])
		if problem != "":
			return problem
	for key: String in MinerPlan.KEYS:
		var data: Dictionary = VALID.duplicate()
		data.erase(key)
		var problem: String = _rejects(data, key)
		if problem != "":
			return "without %s: %s" % [key, problem]
	var extra: Dictionary = VALID.duplicate()
	extra["colour"] = "orange"
	var problem_extra: String = _rejects(extra, "colour")
	if problem_extra != "":
		return problem_extra
	if MinerPlan.parse_json("[1]").error == "" or MinerPlan.parse_json("{").error == "":
		return "a non-object or broken file was accepted"
	return ""


func test_no_plan_no_miners() -> String:
	var level: LevelDef = _level(0, null)
	if not level.miners.is_empty():
		return "a level built without a plan has %d miners" % level.miners.size()
	return ""


func test_same_seed_same_miners_on_every_run() -> String:
	for level_seed: int in PINNED_SEEDS:
		var first_generator: MineGenerator = _inputs.generate(level_seed)
		var first: LevelDef = _inputs.level_of(first_generator)
		var second_generator: MineGenerator = _inputs.generate(level_seed)
		var second: LevelDef = _inputs.level_of(second_generator)
		if first_generator.output_hash() != second_generator.output_hash():
			return "seed %d: output_hash differs between runs" % level_seed
		if first.miners != second.miners:
			return "seed %d: miners %s, then %s" % [level_seed, first.miners, second.miners]
	return ""


## The miners' own stream leaves what came before untouched: on three seeds the
## reactor, every robot and every debris entry are where they are without miners.
func test_miners_leave_reactor_robots_and_debris_unchanged() -> String:
	var many: MinerPlan = MinerPlan.parse_json(JSON.stringify(
			{"count": [5, 5], "min_start_distance": 0, "min_reactor_distance": 0, "min_robot_distance": 0}))
	for level_seed: int in PINNED_SEEDS:
		var without: LevelDef = _level(level_seed, null)
		var with: LevelDef = _level(level_seed, many)
		if with.miners.is_empty():
			return "seed %d: the test plan placed no miners" % level_seed
		if (without.reactor == null) != (with.reactor == null) or without.reactor != null \
				and without.reactor.position_mm != with.reactor.position_mm:
			return "seed %d: the reactor moved" % level_seed
		if without.robots.spawns.size() != with.robots.spawns.size():
			return "seed %d: robot count changed" % level_seed
		for index: int in without.robots.spawns.size():
			if without.robots.spawns[index].position_mm != with.robots.spawns[index].position_mm \
					or without.robots.spawns[index].id != with.robots.spawns[index].id:
				return "seed %d: robot %d moved" % [level_seed, index]
		var a: MeltdownDebris = without.debris
		var b: MeltdownDebris = with.debris
		if (a == null) != (b == null) or a != null and a.size() != b.size():
			return "seed %d: debris changed" % level_seed
	return ""


## Every miner over seeds 0..199 keeps the plan's rules; the spread of 0, 1
## and 2 miners is printed for the pull request.
func test_miners_keep_their_distances_and_spread_is_printed() -> String:
	var plan: MinerPlan = _inputs.miner_plan
	var diameter: int = roundi(2.0 * _inputs.tuning.radius * RobotSpawn.SCALE)
	var spread: Array[int] = [0, 0, 0]
	var noted: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = _inputs.generate(level_seed)
		var level: LevelDef = _inputs.level_of(generator)
		if level.miners.size() > 2:
			return "seed %d: %d miners, above the file's 2" % [level_seed, level.miners.size()]
		spread[level.miners.size()] += 1
		if generator.miner_note != "":
			noted += 1
		var boxes: Array[int] = MinerPlan.reachable_module_boxes(level)
		for index: int in level.miners.size():
			var miner: Vector3i = level.miners[index]
			var problem: String = _rule_broken(level, generator, boxes, miner, plan, diameter)
			if problem != "":
				return "seed %d miner %d: %s" % [level_seed, index, problem]
	print("  miners over seeds 0..%d: 0 miners %d levels, 1 miner %d, 2 miners %d; %d notes"
			% [SEEDS - 1, spread[0], spread[1], spread[2], noted])
	return ""


func _rule_broken(level: LevelDef, generator: MineGenerator, boxes: Array[int], miner: Vector3i,
		plan: MinerPlan, diameter: int) -> String:
	var held: bool = false
	for box: int in boxes:
		var inside: bool = true
		for axis: int in 3:
			if miner[axis] < generator.min_mm[box][axis] + diameter \
					or miner[axis] > generator.max_mm[box][axis] - diameter:
				inside = false
		held = held or inside
	if not held:
		return "not a ship's diameter inside a reachable module box"
	if _distance(miner, level.start_position_mm) < plan.min_start_distance_mm:
		return "too close to the start"
	if level.reactor != null and _distance(miner, level.reactor.position_mm) \
			< maxi(plan.min_reactor_distance_mm, level.reactor.radius_mm + diameter):
		return "too close to the reactor"
	var radii: Dictionary[String, int] = _inputs.robot_radii
	for spawn: RobotSpawn in level.robots.spawns:
		if _distance(miner, spawn.position_mm) < maxi(plan.min_robot_distance_mm, radii[spawn.id] + diameter):
			return "too close to robot %s" % spawn.id
	return ""


func test_fewer_miners_with_a_note_when_none_fit() -> String:
	var far: MinerPlan = MinerPlan.parse_json(JSON.stringify(
			{"count": [2, 2], "min_start_distance": 9000, "min_reactor_distance": 0, "min_robot_distance": 0}))
	var generator: MineGenerator = _inputs.generate(3)
	var level: LevelDef = generator.to_level_def(_inputs.reactor_plan, _inputs.tuning.radius,
			_inputs.robot_plan, _inputs.debris_plan, far)
	if level.error != "" or not level.miners.is_empty():
		return "expected no miners and no error, got %d and \"%s\"" % [level.miners.size(), level.error]
	if not generator.miner_note.contains("0 of 2"):
		return "miner_note \"%s\" does not say 0 of 2" % generator.miner_note
	var failures: Array[String] = _inputs.validate(level, generator)
	if not failures.is_empty():
		return "the level without its miners failed: %s" % failures[0]
	var again: LevelDef = generator.to_level_def(_inputs.reactor_plan, _inputs.tuning.radius,
			_inputs.robot_plan, _inputs.debris_plan, null)
	if generator.miner_note != "" or not again.miners.is_empty():
		return "a rebuild without a plan kept the note \"%s\"" % generator.miner_note
	return ""


static func _distance(a: Vector3i, b: Vector3i) -> int:
	return ceili(Vector3(a - b).length())
