extends RefCounted

## Generated debris keeps clear of robot spawns (#436, RUN-4, GEN-3, ARC-4):
## `min_robot_distance` in `debris.json` is at least a ship's diameter, a spot
## that would put an entry too close to a robot is never used and the entries
## dropped for it are counted in `MineGenerator.debris_note`, and a level with
## no robots places its debris as if the key were not there. The seed sweep in
## `test_generated_debris.gd` checks the distance over seeds 0..999.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEED: int = 42


func _plan_text(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


func test_shipped_distance_is_at_least_a_ship_diameter() -> String:
	var plan: DebrisPlan = DebrisPlan.parse_json(FileAccess.get_file_as_string(DEBRIS_FILE))
	if plan.error != "":
		return "debris.json: %s" % plan.error
	var diameter_mm: int = roundi(2.0 * SeedSweep.ship_radius() * RobotSpawn.SCALE)
	if plan.min_robot_distance_mm < diameter_mm:
		return "min_robot_distance is %d mm, below a ship diameter of %d mm" \
				% [plan.min_robot_distance_mm, diameter_mm]
	var zero: DebrisPlan = _plan_text({"count": [1, 1], "radius": [1, 1], "after_seconds": [5, 5],
			"min_start_distance": 0, "min_reactor_distance": 0, "min_robot_distance": 0})
	return "" if zero.error == "" and zero.min_robot_distance_mm == 0 else "0 m was not accepted: %s" % zero.error


## A robot set right on one escape spot: with the plan asking for an entry on
## every spot, that spot (and any other too close) goes unused, the entry left
## without a spot is counted in the note, and every entry keeps the distance.
## Moved far away, the same robot frees that spot and drops nothing.
func test_a_robot_on_a_route_spot_keeps_debris_off_it() -> String:
	var generator: MineGenerator = MineGenerator.generate(SEED, SeedSweep.load_modules(),
			SeedSweep.MODULE_COUNT, SeedSweep.load_loop_bridges())
	var radius: float = SeedSweep.ship_radius()
	var level: LevelDef = generator.to_level_def(SeedSweep.load_reactor_plan(), radius)
	var spots: Array[Vector3i] = DebrisSpots.escape_spots(generator, level, radius)
	if spots.size() < 3:
		return "seed %d has only %d escape spots" % [SEED, spots.size()]
	var plan: DebrisPlan = _plan_text({"count": [spots.size(), spots.size()], "radius": [1, 1],
			"after_seconds": [5, 5], "min_start_distance": 0, "min_reactor_distance": 0,
			"min_robot_distance": 2})
	if plan.error != "":
		return plan.error
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var target: Vector3i = spots[spots.size() / 2]
	var robot: RobotSpawn = RobotSpawn.new(null, target)
	robot.id = robot_plan.types[0]
	level.robots.spawns.append(robot)
	var debris: MeltdownDebris = plan.place(generator, level, radius, robot_plan)
	if debris == null:
		return "no debris placed: %s" % generator.debris_note
	if debris.positions_mm.has(target):
		return "an entry sits on the robot's spot %s" % target
	var robot_mm: int = robot_plan.radii_mm[0]
	for index: int in debris.size():
		var gap: float = debris.position(index).distance_to(robot.position()) - debris.radius(index) \
				- robot_mm / 1000.0
		if gap < 1.999:
			return "entry %d is %s m from the robot" % [index, gap]
	if not generator.debris_note.contains("dropped for min_robot_distance"):
		return "the note does not count the dropped entries: \"%s\"" % generator.debris_note
	robot.position_mm = Vector3i(9000000, 9000000, 9000000)
	var far: MeltdownDebris = plan.place(generator, level, radius, robot_plan)
	if far == null or not far.positions_mm.has(target):
		return "with the robot far away the spot %s went unused" % target
	if generator.debris_note.contains("min_robot_distance"):
		return "an entry dropped with the robot far away: %s" % generator.debris_note
	return ""


## Without a robot plan the level has no robots, so even a huge
## `min_robot_distance` changes nothing about the debris.
func test_without_robots_debris_is_placed_as_before() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var radius: float = SeedSweep.ship_radius()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))
	var shipped: DebrisPlan = _plan_text(data)
	data["min_robot_distance"] = 10000
	var huge: DebrisPlan = _plan_text(data)
	if shipped.error != "" or huge.error != "":
		return "plans rejected: %s / %s" % [shipped.error, huge.error]
	for level_seed: int in 100:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var a: LevelDef = generator.to_level_def(reactor_plan, radius, null, shipped)
		var b: LevelDef = generator.to_level_def(reactor_plan, radius, null, huge)
		if not a.robots.spawns.is_empty():
			return "seed %d has robots without a robot plan" % level_seed
		if (a.debris == null) != (b.debris == null):
			return "seed %d: debris with one plan only" % level_seed
		if a.debris != null and (a.debris.positions_mm != b.debris.positions_mm
				or a.debris.radii_mm != b.debris.radii_mm or a.debris.after_ticks != b.debris.after_ticks):
			return "seed %d: min_robot_distance changed debris in a level without robots" % level_seed
	return ""
