extends RefCounted

## The validator's `robots` check (#399, GEN-3, CMB-3, ARC-2): a robot must sit
## inside a box with its radius plus a ship's diameter clear of the faces, in a
## box the start reaches, and outside the start module; a level with no robots
## passes; and seeds 0 to 999 with the shipped robot data pass every check.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SHIP_RADIUS: float = 1.0
## Drone-sized: 0.8 m, so the clearance is 2.8 m.
const RADII: Dictionary[String, int] = {"drone": 800}
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 30000


## Box 0: a 10 m tunnel along -z from 0 to -30; box 1 joins it from -29 to
## -60; box 2 reaches box 1 only through a 1 m sliver, so it is unreachable.
func _level(robot_mm: Vector3i) -> LevelDef:
	var level: LevelDef = LevelDef.new()
	level.union = BoxUnion.new([
		BoxBounds.new(Vector3(-5, -5, -30), Vector3(5, 5, 0)),
		BoxBounds.new(Vector3(-5, -5, -60), Vector3(5, 5, -27)),
		BoxBounds.new(Vector3(-5, -5, -90), Vector3(5, 5, -59)),
	] as Array[BoxBounds])
	level.start_position_mm = Vector3i(0, 0, -3000)
	var spawn: RobotSpawn = RobotSpawn.new(null, robot_mm)
	spawn.id = "drone"
	level.robots.spawns.append(spawn)
	return level


func _robot_failures(level: LevelDef, radii: Dictionary[String, int] = RADII,
		start_module: Array[int] = []) -> Array[String]:
	var found: Array[String] = LevelValidator.new().validate(level, SHIP_RADIUS, false, radii, start_module)
	var robots: Array[String] = []
	for message: String in found:
		if message.begins_with("robots:"):
			robots.append(message)
		elif not message.begins_with("reachable:"):
			robots.append("unexpected: " + message)
	return robots


func test_robots_is_listed_last_in_checks() -> String:
	return "" if LevelValidator.CHECKS.back() == "robots" else "CHECKS: %s" % [LevelValidator.CHECKS]


func test_a_level_with_no_robots_passes() -> String:
	var level: LevelDef = _level(Vector3i(0, 0, -45000))
	level.robots.spawns.clear()
	var found: Array[String] = _robot_failures(level)
	return "" if found.is_empty() else "failures: %s" % [found]


func test_a_robot_with_room_in_a_reached_box_passes() -> String:
	var found: Array[String] = _robot_failures(_level(Vector3i(0, 0, -45000)))
	return "" if found.is_empty() else "failures: %s" % [found]


func test_a_robot_inside_a_wall_fails() -> String:
	var found: Array[String] = _robot_failures(_level(Vector3i(8000, 0, -45000)))
	if found.size() != 1 or not found[0].contains("robot 0 (drone)") or not found[0].contains("2.80 m clear"):
		return "expected one robot 0 clearance failure: %s" % [found]
	return ""


func test_a_robot_closer_than_its_clearance_to_a_face_fails() -> String:
	# 2.0 m from the x face: inside the box, but a ship cannot pass it.
	var found: Array[String] = _robot_failures(_level(Vector3i(3000, 0, -45000)))
	return "" if found.size() == 1 and found[0].contains("not held") else "failures: %s" % [found]


func test_a_robot_exactly_its_clearance_from_a_face_passes() -> String:
	# 5 m half width less 2.8 m, to the millimetre, as the generator places them.
	var found: Array[String] = _robot_failures(_level(Vector3i(2200, -2200, -45000)))
	return "" if found.is_empty() else "failures: %s" % [found]


func test_an_unreachable_robot_fails() -> String:
	var found: Array[String] = _robot_failures(_level(Vector3i(0, 0, -80000)))
	if found.size() != 1 or not found[0].contains("box 2, which cannot be reached from start box 0"):
		return "expected one unreachable failure: %s" % [found]
	return ""


func test_a_robot_in_the_start_box_fails_when_no_module_is_given() -> String:
	var found: Array[String] = _robot_failures(_level(Vector3i(0, 0, -15000)))
	if found.size() != 1 or not found[0].contains("inside the start module (box 0)"):
		return "expected one start module failure: %s" % [found]
	return ""


func test_the_start_module_boxes_are_used_when_given() -> String:
	var level: LevelDef = _level(Vector3i(0, 0, -45000))
	var found: Array[String] = _robot_failures(level, RADII, [0, 1] as Array[int])
	if found.size() != 1 or not found[0].contains("inside the start module (box 1)"):
		return "box 1 in the start module passed: %s" % [found]
	found = _robot_failures(_level(Vector3i(0, 0, -15000)), RADII, [1] as Array[int])
	return "" if found.is_empty() else "box 0 outside the given module failed: %s" % [found]


func test_a_robot_of_unknown_radius_fails() -> String:
	var found: Array[String] = _robot_failures(_level(Vector3i(0, 0, -45000)), {} as Dictionary[String, int])
	return "" if found.size() == 1 and found[0].contains("no known radius") else "failures: %s" % [found]


func test_a_resolved_robot_uses_its_own_radius() -> String:
	var level: LevelDef = _level(Vector3i(2500, 0, -45000))
	var def: RobotDef = RobotDef.new()
	def.radius = 0.5
	level.robots.spawns[0].def = def
	# 2.5 m from the face: room for a 0.5 m robot, not for the 0.8 m in RADII.
	var found: Array[String] = _robot_failures(level)
	if not found.is_empty():
		return "the resolved 0.5 m robot failed: %s" % [found]
	level.robots.spawns[0].def = null
	found = _robot_failures(level)
	return "" if found.size() == 1 else "the 0.8 m robot passed: %s" % [found]


func test_the_plan_gives_radii_by_id() -> String:
	var plan: RobotPlan = SeedSweep.load_robot_plan()
	if plan.error != "":
		return "robots.json: %s" % plan.error
	var radii: Dictionary[String, int] = plan.radii_by_id()
	if radii.size() != plan.types.size():
		return "radii %s for types %s" % [radii, plan.types]
	return "" if radii.get("drone", 0) == 800 else "drone radius %s" % radii.get("drone", 0)


func test_seeds_0_to_999_with_robots_pass_every_check() -> String:
	var result: Dictionary = SeedSweep.run(0, SEEDS)
	print(SeedSweep.summary(result))
	if result["failed"] != 0:
		return "%s; first failures: %s" % [SeedSweep.summary(result), result["failures"]]
	if not result["by_check"].has("robots"):
		return "the summary does not count robots: %s" % SeedSweep.summary(result)
	if result["robots"] < SEEDS:
		return "only %d robots placed over %d seeds" % [result["robots"], SEEDS]
	return "" if result["ms"] < TIME_LIMIT_MS else "took %d ms" % result["ms"]
