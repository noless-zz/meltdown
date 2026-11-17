extends RefCounted

## Generated levels place failed blast doors across module openings from the
## `doors` section of `debris.json` (#462, RUN-4, GEN-3, ARC-4, ARC-2): the
## section is checked key by key; a door covers a whole module opening on the
## plane the modules meet in and never one of the start module's; doors leave
## `output_hash`, the reactor, the robots and every sphere entry as they were;
## and over seeds 0..999 every level passes `LevelValidator` and keeps the
## start reachable from the reactor with every entry, doors included, run
## through `DebrisRouteGuard`. The counts of doors placed and held are printed.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 90000
const DOORS: Dictionary = {"count": [1, 2], "thickness": 0.5, "after_seconds": [10, 40],
		"min_start_distance": 15, "min_reactor_distance": 6, "min_robot_distance": 2}


func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))


func _plan(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


## The shipped file without its doors: the spheres alone, as before #462.
func _spheres_only() -> DebrisPlan:
	var data: Dictionary = _file()
	data.erase(DebrisPlan.DOORS_KEY)
	return _plan(data)


func test_the_doors_section_reads() -> String:
	var plan: DebrisPlan = _plan(_file())
	if plan.error != "" or plan.doors == null:
		return "debris.json: %s, doors %s" % [plan.error, plan.doors]
	var doors: DebrisDoors = plan.doors
	if doors.min_count < 0 or doors.max_count < doors.min_count or doors.max_count < 1:
		return "doors.count %d..%d" % [doors.min_count, doors.max_count]
	var data: Dictionary = _file()
	data[DebrisPlan.DOORS_KEY] = DOORS
	var parsed: DebrisPlan = _plan(data)
	if parsed.error != "" or parsed.doors.thickness_mm != 500 or parsed.doors.max_after_ticks != 2400 \
			or parsed.doors.min_start_distance_mm != 15000 or parsed.doors.min_robot_distance_mm != 2000:
		return "DOORS read as \"%s\"" % parsed.error
	return "" if _spheres_only().doors == null else "a file without doors has doors"


func test_a_bad_doors_section_is_rejected_naming_the_key() -> String:
	var cases: Array = [
		["count", [2, 1], "doors.count"], ["count", [0.5, 1], "doors.count"],
		["count", 1, "doors.count"], ["thickness", 0.0, "doors.thickness"],
		["thickness", 9, "doors.thickness"], ["thickness", "thin", "doors.thickness"],
		["after_seconds", [0, 10], "doors.after_seconds"],
		["min_start_distance", -1, "doors.min_start_distance"],
		["min_reactor_distance", "far", "doors.min_reactor_distance"],
		["min_robot_distance", [2], "doors.min_robot_distance"], ["colour", "red", "doors.colour"],
	]
	for case: Array in cases:
		var section: Dictionary = DOORS.duplicate(true)
		section[case[0]] = case[1]
		var problem: String = _rejects(section, [case[2]])
		if problem != "":
			return problem
	for key: String in DOORS:
		var section: Dictionary = DOORS.duplicate(true)
		section.erase(key)
		var problem: String = _rejects(section, ["\"doors.%s\"" % key])
		if problem != "":
			return problem
	var names: Array = []
	for key: String in DebrisDoors.KEYS:
		names.append("\"doors.%s\"" % key)
	var empty: String = _rejects({}, names)
	if empty != "":
		return empty
	return _rejects([], ["doors"])


func _rejects(section: Variant, names: Array) -> String:
	var data: Dictionary = _file()
	data[DebrisPlan.DOORS_KEY] = section
	var plan: DebrisPlan = _plan(data)
	if plan.error == "":
		return "doors %s accepted" % JSON.stringify(section)
	for name: String in names:
		if not plan.error.contains(name):
			return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


func test_seeds_get_doors_across_openings_that_never_close_the_escape() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var validator: LevelValidator = SeedSweep.load_validator()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var plan: DebrisPlan = _plan(_file())
	var spheres: DebrisPlan = _spheres_only()
	var radius: float = SeedSweep.ship_radius()
	var started: int = Time.get_ticks_msec()
	var placed: int = 0
	var held: int = 0
	var on_route: int = 0
	var seeds_with_doors: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var hash_before: int = generator.output_hash()
		var bare: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan, spheres)
		var level: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan, plan)
		var problem: String = _unchanged(bare, level, hash_before, generator.output_hash())
		var doors: Array[int] = _door_entries(level.debris)
		if problem == "":
			problem = _covers_openings(generator, level.debris, doors, plan.doors)
		if problem == "":
			var found: Array[String] = validator.validate(level, radius, true,
					robot_plan.radii_by_id(), SeedSweep.start_module_boxes(generator))
			problem = "" if found.is_empty() else "validator: %s" % found[0]
		var skipped: Array[int] = []
		if problem == "" and level.debris != null:
			problem = _meltdown(level, radius, skipped)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		if doors.is_empty():
			continue
		seeds_with_doors += 1
		placed += doors.size()
		var spots: Array[Vector3i] = DebrisSpots.escape_spots(generator, level, radius)
		for index: int in doors:
			if skipped.has(index):
				held += 1
			if spots.has(level.debris.positions_mm[index]):
				on_route += 1
	print("  doors over seeds 0..%d: %d placed on %d seeds, %d in escape-route modules, %d held by the guard, %d fell"
			% [SEEDS - 1, placed, seeds_with_doors, on_route, held, placed - held])
	if placed == 0 or held == placed:
		return "%d doors placed, %d held: none ever falls" % [placed, held]
	var elapsed: int = Time.get_ticks_msec() - started
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


## Over seeds 0..49 no opening offered to doors joins the start's module, and
## every other module join is offered.
func test_the_start_modules_openings_get_no_door() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	for level_seed: int in 50:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var start: int = generator.open_owner[0].x
		var offered: Array[int] = DebrisDoors.openings(generator)
		for index: int in generator.placements.size():
			var placement: ModulePlacement = generator.placements[index]
			if placement.door_box < 0:
				continue
			var at_start: bool = index == start or placement.parent == start
			if offered.has(placement.door_box) == at_start:
				return "seed %d: opening box %d (module %d, start module %d) offered %s" \
						% [level_seed, placement.door_box, index, start, not at_start]
	return ""


func _door_entries(debris: MeltdownDebris) -> Array[int]:
	var found: Array[int] = []
	if debris == null:
		return found
	for index: int in debris.size():
		if debris.is_box(index):
			found.append(index)
	return found


## Every sphere entry, the reactor, the robots and `output_hash` as without doors,
## and the doors after the spheres.
func _unchanged(bare: LevelDef, level: LevelDef, hash_before: int, hash_after: int) -> String:
	if hash_before != hash_after:
		return "placing doors changed output_hash"
	if (bare.reactor == null) != (level.reactor == null) \
			or (bare.reactor != null and bare.reactor.to_json() != level.reactor.to_json()):
		return "the reactor changed with doors"
	if bare.robots.spawns.size() != level.robots.spawns.size():
		return "the robots changed with doors"
	for index: int in bare.robots.spawns.size():
		if bare.robots.spawns[index].position_mm != level.robots.spawns[index].position_mm:
			return "robot %d moved with doors" % index
	var spheres: int = 0 if bare.debris == null else bare.debris.size()
	if spheres > 0 and level.debris == null:
		return "the spheres went with doors"
	for index: int in spheres:
		if level.debris.is_box(index) or level.debris.positions_mm[index] != bare.debris.positions_mm[index] \
				or level.debris.radii_mm[index] != bare.debris.radii_mm[index] \
				or level.debris.after_ticks[index] != bare.debris.after_ticks[index]:
			return "sphere %d changed with doors" % index
	if level.debris != null:
		for index: int in range(spheres, level.debris.size()):
			if not level.debris.is_box(index):
				return "entry %d after the spheres is not a door" % index
	return ""


## Each door sits on the meeting plane of a module join that is not the
## start module's, covers its whole opening square, has the file's thickness
## and falls within the file's times.
func _covers_openings(generator: MineGenerator, debris: MeltdownDebris, doors: Array[int],
		section: DebrisDoors) -> String:
	var openings: Array[int] = DebrisDoors.openings(generator)
	var used: Array[int] = []
	for index: int in doors:
		var box: int = -1
		for candidate: int in openings:
			if (generator.min_mm[candidate] + generator.max_mm[candidate]) / 2 == debris.positions_mm[index]:
				box = candidate
		if box < 0:
			return "door %d at %s is not centred on a module opening" % [index, debris.position(index)]
		if used.has(box):
			return "two doors on opening box %d" % box
		used.append(box)
		var extent: Vector3i = generator.max_mm[box] - generator.min_mm[box]
		var size: Vector3i = debris.sizes_mm[index]
		var thin: int = 0
		for axis: int in 3:
			if size[axis] < size[thin]:
				thin = axis
		for axis: int in 3:
			var want: int = section.thickness_mm if axis == thin else extent[axis]
			if size[axis] != want:
				return "door %d is %s mm, opening box %d is %s mm" % [index, size, box, extent]
		if extent[thin] != 2 * MineGenerator.DOOR_DEPTH_MM:
			return "door %d is thin along an axis the opening does not run through" % index
		var ticks: int = debris.after_ticks[index]
		if ticks < section.min_after_ticks or ticks > section.max_after_ticks:
			return "door %d falls after %d ticks, outside the file's range" % [index, ticks]
	return ""


## Every entry falls due in order through `DebrisRouteGuard` with a ship at the
## reactor; the start must stay reachable. `skipped` gets the held entries.
func _meltdown(level: LevelDef, radius: float, skipped: Array[int]) -> String:
	var sim: Sim = Sim.new(0, 1)
	sim.set_walls(level.union)
	sim.set_start_pose(0, level.start_position(), Basis())
	sim.ships[0].radius = radius
	sim.ships[0].position = level.reactor.position()
	var reactor: ReactorState = level.reactor.fresh_copy()
	reactor.destroyed = true
	sim.set_reactor(reactor)
	sim.set_debris(level.debris.fresh_copy())
	var due: Array[int] = []
	for ticks: int in sim.debris.after_ticks:
		if not due.has(ticks):
			due.append(ticks)
	due.sort()
	var events: Array[SimEvent] = []
	var all: Array[int] = []
	for box: int in level.union.boxes.size():
		all.append(box)
	for ticks: int in due:
		sim.debris.elapsed_ticks = ticks - 1
		DebrisRouteGuard.advance(sim, events)
		var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
				level.start_position(), sim.debris, radius)
		if route.length_mm == EscapePath.UNREACHABLE:
			return "debris %d ticks in closed every route out: %s" % [ticks, sim.debris.to_json()]
	for index: int in sim.debris.size():
		if sim.debris.is_skipped(index):
			skipped.append(index)
	return ""
