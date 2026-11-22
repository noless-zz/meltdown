extends RefCounted

## At most `max_near_start` robots within `near_start_distance` of the start
## (#531, GEN-3, ARC-4, ARC-2): the shipped file reads both keys, no level of
## seeds 0..999 breaks the rule, the cap costs at most 10% of the robots placed
## on average against the same file with no cap, and the same seed gives the
## same robots on every run.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const SEEDS: int = 1000
const REPEAT_SEEDS: int = 100
## Largest allowed drop in the average robots per level, as a fraction.
const MAX_DROP: float = 0.10


func _shipped_text() -> String:
	return FileAccess.get_file_as_string(SeedLevel.ROBOTS_FILE)


func _plan(text: String) -> RobotPlan:
	return RobotPlan.parse_json(text, SeedLevel.robot_texts())


## The shipped file with the cap lifted, which places as `main` did before #531.
func _uncapped_plan() -> RobotPlan:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data["max_near_start"] = 1000
	return _plan(JSON.stringify(data))


## Levels are built with the shipped loop bridges, as `seed_sweep.gd` and the
## player's levels are.
func _levels(plan: RobotPlan, first: int, count: int, shared: bool = true) -> Array[LevelDef]:
	var inputs: SeedLevel = SeedLevelCache.inputs()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var ship_radius: float = SeedSweep.ship_radius()
	var levels: Array[LevelDef] = []
	for level_seed: int in range(first, first + count):
		# The shipped generator, shared with the seed sweeps
		# (`seed_level_cache.gd`, #1139) unless `shared` is false; only the
		# level built from it is ours.
		var generator: MineGenerator = SeedLevelCache.generator(level_seed) if shared \
				else inputs.generate(level_seed)
		levels.append(generator.to_level_def(reactor_plan, ship_radius, plan))
	return levels


## Robots strictly within `distance_mm` of the start, in whole millimetres as
## placement measures them.
static func _near_start(level: LevelDef, distance_mm: int) -> int:
	var count: int = 0
	for spawn: RobotSpawn in level.robots.spawns:
		var d: Vector3i = spawn.position_mm - level.start_position_mm
		if d.x * d.x + d.y * d.y + d.z * d.z < distance_mm * distance_mm:
			count += 1
	return count


func test_shipped_file_reads_the_near_start_keys() -> String:
	var plan: RobotPlan = _plan(_shipped_text())
	if plan.error != "":
		return "robots.json: %s" % plan.error
	if plan.near_start_distance_mm != 40000 or plan.max_near_start != 2:
		return "read near_start_distance %d mm, max_near_start %d" \
				% [plan.near_start_distance_mm, plan.max_near_start]
	if plan.near_start_distance_mm < plan.min_start_distance_mm:
		return "near_start_distance is inside min_start_distance, so the cap does nothing"
	return ""


func test_no_level_breaks_the_rule_and_robots_drop_at_most_ten_percent() -> String:
	var plan: RobotPlan = _plan(_shipped_text())
	var capped: Array[LevelDef] = _levels(plan, 0, SEEDS)
	var uncapped: Array[LevelDef] = _levels(_uncapped_plan(), 0, SEEDS)
	var with_cap: int = 0
	var without_cap: int = 0
	var broke_before: int = 0
	for index: int in SEEDS:
		var near: int = _near_start(capped[index], plan.near_start_distance_mm)
		if near > plan.max_near_start:
			return "seed %d: %d robots within %d mm of the start, cap %d" \
					% [index, near, plan.near_start_distance_mm, plan.max_near_start]
		if _near_start(uncapped[index], plan.near_start_distance_mm) > plan.max_near_start:
			broke_before += 1
		with_cap += capped[index].robots.spawns.size()
		without_cap += uncapped[index].robots.spawns.size()
	if broke_before == 0:
		return "no seed broke the rule without the cap, so this test proves nothing"
	if float(with_cap) < float(without_cap) * (1.0 - MAX_DROP):
		return "robots placed fell from %d to %d over %d seeds" % [without_cap, with_cap, SEEDS]
	return ""


func test_cap_of_zero_keeps_every_robot_out_of_the_near_zone() -> String:
	var data: Dictionary = JSON.parse_string(_shipped_text())
	data["max_near_start"] = 0
	var plan: RobotPlan = _plan(JSON.stringify(data))
	if plan.error != "":
		return "max_near_start 0 rejected: %s" % plan.error
	var levels: Array[LevelDef] = _levels(plan, 0, REPEAT_SEEDS)
	for index: int in levels.size():
		if _near_start(levels[index], plan.near_start_distance_mm) != 0:
			return "seed %d has a robot near the start with a cap of 0" % index
	return ""


func test_same_seeds_same_robots_on_every_run() -> String:
	var plan: RobotPlan = _plan(_shipped_text())
	var first: Array[LevelDef] = _levels(plan, 0, REPEAT_SEEDS)
	# Generated afresh, so the second run repeats the generator too.
	var second: Array[LevelDef] = _levels(plan, 0, REPEAT_SEEDS, false)
	for index: int in REPEAT_SEEDS:
		var a: Array[RobotSpawn] = first[index].robots.spawns
		var b: Array[RobotSpawn] = second[index].robots.spawns
		if a.size() != b.size():
			return "seed %d: %d robots, then %d" % [index, a.size(), b.size()]
		for robot: int in a.size():
			if a[robot].id != b[robot].id or a[robot].position_mm != b[robot].position_mm \
					or a[robot].facing_mm != b[robot].facing_mm:
				return "seed %d robot %d differs between runs" % [index, robot]
	return ""
