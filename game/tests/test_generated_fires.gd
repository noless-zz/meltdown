extends RefCounted

## Generated levels place fire from the `fires` section of `debris.json` (#497,
## RUN-4, GEN-2, GEN-3, ARC-4): the section is checked key by key; fires come
## after every solid entry and leave `output_hash`, the reactor, the robots and
## every solid entry as they were; and over seeds 0..999 every level with fire
## passes `LevelValidator`'s `debris_escape` check (timed with the fires down,
## since they are placed after `DebrisEscape.trim`) and the debris sweep, and
## every fire lies inside the level,
## outside the start module and within the section's ranges and distances. The
## count of fires placed is printed.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
## Twice #903's 15 s target, for the CI runner's run-to-run spread, so a
## slow-down fails here instead of going unnoticed.
const TIME_LIMIT_MS: int = 30000
const FIRES: Dictionary = {"count": [1, 2], "radius": [2, 3], "damage_per_second": 5,
		"after_fraction": [0.05, 0.2], "min_start_distance": 15, "min_reactor_distance": 6,
		"min_robot_distance": 2}


func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))


func _plan(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


## The shipped file without its fires: spheres and doors, as before #497.
func _solid_only() -> DebrisPlan:
	var data: Dictionary = _file()
	data.erase(DebrisPlan.FIRES_KEY)
	return _plan(data)


func test_the_fires_section_reads() -> String:
	var plan: DebrisPlan = _plan(_file())
	if plan.error != "" or plan.fires == null:
		return "debris.json: %s, fires %s" % [plan.error, plan.fires]
	var fires: DebrisFires = plan.fires
	if fires.min_count < 0 or fires.max_count < fires.min_count or fires.max_count < 1:
		return "fires.count %d..%d" % [fires.min_count, fires.max_count]
	var data: Dictionary = _file()
	data[DebrisPlan.FIRES_KEY] = FIRES.duplicate(true)
	var parsed: DebrisPlan = _plan(data)
	if parsed.error != "":
		return "FIRES read as \"%s\"" % parsed.error
	var read: DebrisFires = parsed.fires
	if read.min_count != 1 or read.max_count != 2 or read.min_radius_mm != 2000 \
			or read.max_radius_mm != 3000 or read.milli_dps != 5000 or read.min_after_permille != 50 \
			or read.max_after_permille != 200 or read.min_start_distance_mm != 15000 \
			or read.min_reactor_distance_mm != 6000 or read.min_robot_distance_mm != 2000:
		return "FIRES read with the wrong values"
	data[DebrisPlan.FIRES_KEY]["count"] = [0, 0]
	if _plan(data).error != "":
		return "a count of 0 was rejected: %s" % _plan(data).error
	return "" if _solid_only().fires == null else "a file without fires has fires"


func test_a_bad_fires_section_is_rejected_naming_the_key() -> String:
	var cases: Array = [
		["count", [2, 1], "fires.count"], ["count", [0.5, 1], "fires.count"],
		["count", 1, "fires.count"], ["radius", [0, 2], "fires.radius"],
		["radius", [3, 2], "fires.radius"], ["radius", [1, 99], "fires.radius"],
		["damage_per_second", 0, "fires.damage_per_second"],
		["damage_per_second", -3, "fires.damage_per_second"],
		["damage_per_second", "hot", "fires.damage_per_second"],
		["damage_per_second", 1000000, "fires.damage_per_second"],
		["after_fraction", [0, 0.1], "fires.after_fraction"],
		["after_fraction", [0.2, 0.1], "fires.after_fraction"],
		["after_fraction", [0.1, 1.5], "fires.after_fraction"],
		["after_fraction", [5, 10], "fires.after_fraction"],
		["after_fraction", 0.1, "fires.after_fraction"],
		["after_seconds", [10, 50], "fires.after_seconds"],
		["min_start_distance", -1, "fires.min_start_distance"],
		["min_reactor_distance", "far", "fires.min_reactor_distance"],
		["min_robot_distance", [2], "fires.min_robot_distance"], ["colour", "red", "fires.colour"],
	]
	for case: Array in cases:
		var section: Dictionary = FIRES.duplicate(true)
		section[case[0]] = case[1]
		var problem: String = _rejects(section, [case[2]])
		if problem != "":
			return problem
	for key: String in FIRES:
		var section: Dictionary = FIRES.duplicate(true)
		section.erase(key)
		var problem: String = _rejects(section, ["\"fires.%s\"" % key])
		if problem != "":
			return problem
	var names: Array = []
	for key: String in DebrisFires.KEYS:
		names.append("\"fires.%s\"" % key)
	var empty: String = _rejects({}, names)
	if empty != "":
		return empty
	return _rejects([], ["fires"])


func _rejects(section: Variant, names: Array) -> String:
	var data: Dictionary = _file()
	data[DebrisPlan.FIRES_KEY] = section
	var plan: DebrisPlan = _plan(data)
	if plan.error == "":
		return "fires %s accepted" % JSON.stringify(section)
	for name: String in names:
		if not plan.error.contains(name):
			return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


func test_the_same_seed_places_the_same_fires() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var data: Dictionary = _file()
	data[DebrisPlan.FIRES_KEY] = FIRES
	var lists: Array[String] = []
	for run: int in 2:
		var generator: MineGenerator = MineGenerator.generate(7, modules, SeedSweep.MODULE_COUNT,
				bridges)
		var level: LevelDef = generator.to_level_def(SeedSweep.load_reactor_plan(),
				SeedSweep.ship_radius(), SeedSweep.load_robot_plan(), _plan(data))
		if level.debris == null or _fire_entries(level.debris).is_empty():
			return "seed 7 got no fire"
		lists.append(level.debris.to_json())
	return "" if lists[0] == lists[1] else "seed 7 placed different debris twice"


func test_seeds_get_fires_inside_the_level_that_change_nothing_solid() -> String:
	var validator: LevelValidator = SeedSweep.load_validator()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var plan: DebrisPlan = _plan(_file())
	var radius: float = SeedSweep.ship_radius()
	# Every seed is generated and built once for all the sweeps that read it
	# (#903, #956): the shipped level, and the same level without the fires
	# section. Getting them is timed on its own, and the limit is on this
	# sweep's checks.
	var preparing: int = Time.get_ticks_msec()
	var bares: Array[LevelDef] = []
	var levels: Array[LevelDef] = []
	for level_seed: int in SEEDS:
		bares.append(SeedLevelCache.level(level_seed, SeedLevelCache.WITHOUT_FIRES))
		levels.append(SeedLevelCache.level(level_seed))
	var started: int = Time.get_ticks_msec()
	var placed: int = 0
	var seeds_with_fire: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = SeedLevelCache.generator(level_seed)
		var bare: LevelDef = bares[level_seed]
		var level: LevelDef = levels[level_seed]
		var problem: String = _unchanged(bare, level, SeedLevelCache.generated_hash(level_seed),
				generator.output_hash())
		var fires: Array[int] = _fire_entries(level.debris)
		if problem == "":
			problem = _fires_fit(generator, level, fires, plan, robot_plan)
		# The escape timed with every entry, fires too, fallen: the one validator
		# check fire takes part in. The others see only the level's boxes,
		# reactor, robots and solid entries, which `_unchanged` has just shown
		# are those of the level without fire, and `test_level_validator.gd`'s
		# sweep runs every check on the same generated levels, fires and all, over
		# seeds 1..1000 (#903: running the whole validator here too was about a
		# tenth of this sweep's time).
		if problem == "" and not fires.is_empty():
			problem = DebrisEscape.failure(level, level.debris, radius,
					validator.escape_speed_mps, validator.escape_margin)
		if problem == "" and level.debris != null:
			problem = _meltdown(level, radius, fires)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		if not fires.is_empty():
			seeds_with_fire += 1
			placed += fires.size()
	var elapsed: int = Time.get_ticks_msec() - started
	var shared_ms: int = SeedLevelCache.generate_ms
	for variant: String in SeedLevelCache.VARIANTS:
		shared_ms += SeedLevelCache.build_ms[variant]
	print("  fires over seeds 0..%d: %d placed on %d seeds in %d ms (waited %d ms for shared levels; all sweeps: generating %d ms, building %s ms)" % [
			SEEDS - 1, placed, seeds_with_fire, elapsed, started - preparing,
			SeedLevelCache.generate_ms, SeedLevelCache.build_ms])
	if placed == 0:
		return "no fire placed over seeds 0..%d" % (SEEDS - 1)
	# The other sweeps read these generators and levels instead of timing their
	# own, so a slow generator or level build still fails here, whichever sweep
	# made them.
	if shared_ms > TIME_LIMIT_MS:
		return "generating and building the shared levels took %d ms, limit %d" % [shared_ms, TIME_LIMIT_MS]
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


func _fire_entries(debris: MeltdownDebris) -> Array[int]:
	var found: Array[int] = []
	if debris == null:
		return found
	for index: int in debris.size():
		if debris.is_fire(index):
			found.append(index)
	return found


## `output_hash`, the reactor, the robots and every solid entry as without
## fires, and the fires after every solid entry.
func _unchanged(bare: LevelDef, level: LevelDef, hash_before: int, hash_after: int) -> String:
	if hash_before != hash_after:
		return "placing fires changed output_hash"
	if (bare.reactor == null) != (level.reactor == null) \
			or (bare.reactor != null and bare.reactor.to_json() != level.reactor.to_json()):
		return "the reactor changed with fires"
	if bare.robots.spawns.size() != level.robots.spawns.size():
		return "the robots changed with fires"
	for index: int in bare.robots.spawns.size():
		if bare.robots.spawns[index].position_mm != level.robots.spawns[index].position_mm:
			return "robot %d moved with fires" % index
	var solid: int = 0 if bare.debris == null else bare.debris.size()
	if solid > 0 and level.debris == null:
		return "the solid entries went with fires"
	for index: int in solid:
		if level.debris.is_fire(index) or level.debris.positions_mm[index] != bare.debris.positions_mm[index] \
				or level.debris.radii_mm[index] != bare.debris.radii_mm[index] \
				or level.debris.is_box(index) != bare.debris.is_box(index) \
				or level.debris.box_size(index) != bare.debris.box_size(index) \
				or level.debris.after_ticks[index] != bare.debris.after_ticks[index]:
			return "solid entry %d changed with fires" % index
	if level.debris != null:
		for index: int in range(solid, level.debris.size()):
			if not level.debris.is_fire(index):
				return "entry %d after the solid entries is not a fire" % index
	return ""


## Each fire is a sphere wholly inside one module box, clear of every start
## module box, within the section's ranges and the fall limit, and keeps the
## section's distances from the start, the reactor and the robots.
func _fires_fit(generator: MineGenerator, level: LevelDef, fires: Array[int], plan: DebrisPlan,
		robot_plan: RobotPlan) -> String:
	var section: DebrisFires = plan.fires
	var debris: MeltdownDebris = level.debris
	var start_boxes: Array[int] = SeedSweep.start_module_boxes(generator)
	var radii: Array[int] = DebrisPlan.robot_radii_mm(level, robot_plan)
	if fires.is_empty():
		return ""
	# Each is an escape path search, the same for every fire of the level.
	var countdown: int = DebrisPlan.countdown_ticks(level)
	var limit: int = plan.fall_limit_ticks(level)
	for index: int in fires:
		var at: Vector3i = debris.positions_mm[index]
		var r: int = debris.radii_mm[index]
		if debris.is_box(index) or r < section.min_radius_mm or r > section.max_radius_mm:
			return "fire %d radius %d mm outside the section" % [index, r]
		if debris.fire_milli_dps[index] != section.milli_dps:
			return "fire %d burns %d milli per second" % [index, debris.fire_milli_dps[index]]
		var ticks: int = debris.after_ticks[index]
		var earliest: int = DebrisFires.after_ticks(section.min_after_permille, countdown, limit)
		var latest: int = DebrisFires.after_ticks(section.max_after_permille, countdown, limit)
		if ticks < earliest or ticks > latest:
			return "fire %d starts after %d ticks, outside %d..%d of a %d-tick countdown" % [
					index, ticks, earliest, latest, countdown]
		var inside: bool = false
		for box: int in generator.min_mm.size():
			var low: Vector3i = generator.min_mm[box] + Vector3i(r, r, r)
			var high: Vector3i = generator.max_mm[box] - Vector3i(r, r, r)
			if at.clamp(low, high) == at and not start_boxes.has(box):
				inside = true
		if not inside or not level.union.holds(debris.position(index), 0.0):
			return "fire %d at %s is not wholly inside a module box" % [index, debris.position(index)]
		for box: int in start_boxes:
			if DebrisFires.gap_squared(generator, box, at) <= r * r:
				return "fire %d at %s reaches start module box %d" % [index, debris.position(index), box]
		var position: Vector3 = debris.position(index)
		var radius_m: float = r / 1000.0
		if position.distance_to(level.start_position()) - radius_m \
				< section.min_start_distance_mm / 1000.0 - 0.001:
			return "fire %d is too close to the start" % index
		if level.reactor != null and position.distance_to(level.reactor.position()) - radius_m \
				- level.reactor.radius() < section.min_reactor_distance_mm / 1000.0 - 0.001:
			return "fire %d is too close to the reactor" % index
		for spawn: int in level.robots.spawns.size():
			var gap: float = position.distance_to(level.robots.spawns[spawn].position()) - radius_m \
					- radii[spawn] / 1000.0
			if gap < section.min_robot_distance_mm / 1000.0 - 0.001:
				return "fire %d is too close to robot %d" % [index, spawn]
	return ""


## Every entry falls due in order through the route guard with a ship at the
## reactor; the start must stay reachable and no fire is ever held back.
##
## The fall order is `SeedSweep.debris_route`, which gives what flying the
## meltdown gives without flying it (#513; `test_seed_sweep_debris.gd`
## compares the two): flying it was over half of this sweep's time (#903).
## Each fire is still put through `DebrisRouteGuard.advance` itself on the tick
## it lights, so a guard that began holding fire back would fail here.
func _meltdown(level: LevelDef, radius: float, fires: Array[int]) -> String:
	var held: Array[int] = []
	var held_flags: Array[bool] = []
	var closed: String = SeedSweep.debris_route(level, radius, held, true, held_flags)
	if closed != "":
		return closed
	for index: int in fires:
		if index < held_flags.size() and held_flags[index]:
			return "the guard's fall order held back fire %d" % index
	if fires.is_empty():
		return ""
	var sim: Sim = Sim.new(0, 1)
	sim.set_walls(level.union)
	sim.set_start_pose(0, level.start_position(), Basis())
	sim.ships[0].radius = radius
	sim.ships[0].position = level.reactor.position()
	var reactor: ReactorState = level.reactor.fresh_copy()
	reactor.destroyed = true
	sim.set_reactor(reactor)
	sim.set_debris(level.debris.fresh_copy())
	var lit: Array[int] = []
	for index: int in fires:
		if not lit.has(sim.debris.after_ticks[index]):
			lit.append(sim.debris.after_ticks[index])
	lit.sort()
	var events: Array[SimEvent] = []
	for ticks: int in lit:
		sim.debris.elapsed_ticks = ticks - 1
		DebrisRouteGuard.advance(sim, events)
	for index: int in fires:
		if sim.debris.is_skipped(index):
			return "the guard held back fire %d" % index
	return ""
