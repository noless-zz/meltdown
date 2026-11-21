extends RefCounted

## Generated levels place cave-ins inside straight tunnels from the `caveins`
## section of `debris.json` (#514, RUN-4, GEN-3, ARC-4, ARC-2): the section is
## checked key by key; only straight tunnels other than the start's module are
## offered; a cave-in is centred on the tunnel's line, square to it, covers its
## whole cross-section and splits its box for the route model (#868, #869); and
## over seeds 0..999 the cave-ins leave `output_hash`, the reactor, the robots
## and every other entry as they were, every level with one passes
## `LevelValidator` (`debris_escape` included), and the guard keeps the way out
## open. How many were placed, held and fell is printed.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 30000
const CAVEINS: Dictionary = {"count": [1, 2], "thickness": 1.5, "after_seconds": [5, 40],
		"min_start_distance": 10, "min_reactor_distance": 4, "min_robot_distance": 1}


func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))


func _plan(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


## The shipped file without its cave-ins, as before #514.
func _without_caveins() -> DebrisPlan:
	var data: Dictionary = _file()
	data.erase(DebrisPlan.CAVEINS_KEY)
	return _plan(data)


func test_the_caveins_section_reads() -> String:
	var plan: DebrisPlan = _plan(_file())
	if plan.error != "" or plan.caveins == null:
		return "debris.json: %s, caveins %s" % [plan.error, plan.caveins]
	var shipped: DebrisCaveins = plan.caveins
	if shipped.min_count != 0 or shipped.max_count != 1 or shipped.thickness_mm != 1000:
		return "shipped caveins count %d..%d, thickness %d mm" % [shipped.min_count,
				shipped.max_count, shipped.thickness_mm]
	var data: Dictionary = _file()
	data[DebrisPlan.CAVEINS_KEY] = CAVEINS.duplicate(true)
	var parsed: DebrisPlan = _plan(data)
	if parsed.error != "":
		return "CAVEINS read as \"%s\"" % parsed.error
	var read: DebrisCaveins = parsed.caveins
	if read.min_count != 1 or read.max_count != 2 or read.thickness_mm != 1500 \
			or read.min_after_ticks != 5 * MeltdownDebris.TICKS_PER_SECOND \
			or read.max_after_ticks != 40 * MeltdownDebris.TICKS_PER_SECOND \
			or read.min_start_distance_mm != 10000 or read.min_reactor_distance_mm != 4000 \
			or read.min_robot_distance_mm != 1000:
		return "CAVEINS read with the wrong values"
	return "" if _without_caveins().caveins == null else "a file without caveins has cave-ins"


func test_a_bad_caveins_section_is_rejected_naming_the_key() -> String:
	var cases: Array = [
		["count", [2, 1], "caveins.count"], ["count", [0.5, 1], "caveins.count"],
		["count", 1, "caveins.count"], ["thickness", 0, "caveins.thickness"],
		["thickness", 11, "caveins.thickness"], ["thickness", "thick", "caveins.thickness"],
		["after_seconds", [0, 10], "caveins.after_seconds"],
		["after_seconds", [20, 10], "caveins.after_seconds"],
		["after_seconds", 10, "caveins.after_seconds"],
		["min_start_distance", -1, "caveins.min_start_distance"],
		["min_reactor_distance", "far", "caveins.min_reactor_distance"],
		["min_robot_distance", [2], "caveins.min_robot_distance"],
		["loop_weight", 2, "caveins.loop_weight"],
	]
	for case: Array in cases:
		var section: Dictionary = CAVEINS.duplicate(true)
		section[case[0]] = case[1]
		var problem: String = _rejects(section, [case[2]])
		if problem != "":
			return problem
	for key: String in CAVEINS:
		var section: Dictionary = CAVEINS.duplicate(true)
		section.erase(key)
		var problem: String = _rejects(section, ["\"caveins.%s\"" % key])
		if problem != "":
			return problem
	var names: Array = []
	for key: String in DebrisCaveins.KEYS:
		names.append("\"caveins.%s\"" % key)
	var empty: String = _rejects({}, names)
	if empty != "":
		return empty
	return _rejects([], ["caveins"])


func _rejects(section: Variant, names: Array) -> String:
	var data: Dictionary = _file()
	data[DebrisPlan.CAVEINS_KEY] = section
	var plan: DebrisPlan = _plan(data)
	if plan.error == "":
		return "caveins %s accepted" % JSON.stringify(section)
	for name: String in names:
		if not plan.error.contains(name):
			return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


## Over seeds 0..49 exactly the straight tunnels other than the start's module
## are offered: never a room, a corner or a shaft with a side door.
func test_only_straight_tunnels_outside_the_start_module_are_offered() -> String:
	var modules: Dictionary[String, ModuleDef] = {}
	for module: ModuleDef in SeedSweep.load_modules():
		modules[module.id] = module
	var offered_any: bool = false
	for generator: MineGenerator in SeedSweep.shared_generators(0, 50):
		var start: int = generator.open_owner[0].x
		var offered: Array[int] = DebrisCaveins.tunnels(generator)
		for index: int in generator.placements.size():
			var placement: ModulePlacement = generator.placements[index]
			var module: ModuleDef = modules[placement.module_id]
			if placement.connectors.size() != module.connectors.size():
				return "module %d keeps %d of %d connectors" % [index, placement.connectors.size(),
						module.connectors.size()]
			var want: bool = placement.module_id == "straight_tunnel" and index != start
			if offered.has(index) != want:
				return "module %d (%s, start %d) offered %s" % [index, placement.module_id, start,
						offered.has(index)]
			offered_any = offered_any or want
	return "" if offered_any else "no straight tunnel offered over seeds 0..49"


## A tunnel's cave-in sits mid-way along it, covers its cross-section, is
## `thickness` deep, and on its own splits the tunnel's box across the tunnel
## (`BoxSplit`, which the route model, the map, the guard and the bot share).
func test_a_cavein_closes_its_tunnel_for_the_route_model() -> String:
	var plan: DebrisPlan = _plan(_file())
	var radius: float = SeedSweep.ship_radius()
	for generator: MineGenerator in SeedSweep.shared_generators(0, 20):
		for placement: int in DebrisCaveins.tunnels(generator):
			var problem: String = _closes(generator, placement, plan.caveins, radius)
			if problem != "":
				return problem
	return ""


func _closes(generator: MineGenerator, placement: int, section: DebrisCaveins,
		radius: float) -> String:
	var owned: ModulePlacement = generator.placements[placement]
	var a: ModuleConnector = owned.connectors[0]
	var b: ModuleConnector = owned.connectors[1]
	var centre: Vector3i = DebrisCaveins.centre_mm(generator, placement)
	if centre * 2 != a.position_mm + b.position_mm:
		return "cave-in in module %d is not mid-way between its connectors" % placement
	var size: Vector3i = section.size_mm(generator, placement)
	var box: int = owned.first_box
	for axis: int in 3:
		if axis == a.axis():
			if size[axis] != section.thickness_mm:
				return "cave-in in module %d is %d mm deep" % [placement, size[axis]]
		elif centre[axis] - size[axis] / 2 > generator.min_mm[box][axis] \
				or centre[axis] + size[axis] / 2 < generator.max_mm[box][axis]:
			return "cave-in in module %d leaves room across axis %d" % [placement, axis]
	var debris: MeltdownDebris = MeltdownDebris.new()
	debris.positions_mm.append(centre)
	debris.radii_mm.append(0)
	debris.sizes_mm.append(size)
	debris.after_ticks.append(1)
	debris.skipped.append(false)
	debris.elapsed_ticks = 1
	var cuts: Array[Vector3i] = BoxSplit.splits(generator.min_mm[box], generator.max_mm[box], debris,
			roundi(radius * RobotSpawn.SCALE))
	if not cuts.has(Vector3i(0, a.axis(), centre[a.axis()])):
		return "cave-in in module %d does not split its box across the tunnel: %s" % [placement, cuts]
	return ""


func test_seeds_get_caveins_that_change_nothing_else_and_keep_the_escape() -> String:
	var validator: LevelValidator = SeedSweep.load_validator()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var plan: DebrisPlan = _plan(_file())
	var bare_plan: DebrisPlan = _without_caveins()
	var radius: float = SeedSweep.ship_radius()
	var started: int = Time.get_ticks_msec()
	var placed: int = 0
	var held: int = 0
	var seeds_with: int = 0
	for level_seed: int in SEEDS:
		# The generator and the shipped level are shared with the other sweeps
		# (#956); the level without cave-ins is this sweep's own.
		var generator: MineGenerator = SeedLevelCache.generator(level_seed)
		var bare: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan, bare_plan)
		var level: LevelDef = SeedLevelCache.level(level_seed)
		var caveins: Array[int] = []
		var problem: String = _unchanged(bare, level, SeedLevelCache.generated_hash(level_seed),
				generator.output_hash(), caveins)
		if problem == "":
			problem = _fit(generator, level, caveins, plan)
		if problem == "" and not caveins.is_empty():
			var found: Array[String] = validator.validate(level, radius, true,
					robot_plan.radii_by_id(), SeedSweep.start_module_boxes(generator))
			problem = "" if found.is_empty() else "validator: %s" % found[0]
		var count: Array[int] = []
		var flags: Array[bool] = []
		if problem == "" and not caveins.is_empty():
			problem = SeedSweep.debris_route(level, radius, count, true, flags)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		if caveins.is_empty():
			continue
		seeds_with += 1
		placed += caveins.size()
		for index: int in caveins:
			if index < flags.size() and flags[index]:
				held += 1
	var elapsed: int = Time.get_ticks_msec() - started
	print("  cave-ins over seeds 0..%d: %d placed on %d seeds, %d held by the guard, %d fell (%d ms)"
			% [SEEDS - 1, placed, seeds_with, held, placed - held, elapsed])
	if placed == 0 or held == placed:
		return "%d cave-ins placed, %d held: none ever falls" % [placed, held]
	# The guard must be seen holding one that would close the last way out.
	if held == 0:
		return "%d cave-ins placed and none held by the guard" % placed
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


## `output_hash`, the reactor, the robots and every entry as without cave-ins:
## the solid entries first, then the cave-ins, then the fires. `caveins` gets
## the cave-ins' indices.
func _unchanged(bare: LevelDef, level: LevelDef, hash_before: int, hash_after: int,
		caveins: Array[int]) -> String:
	if hash_before != hash_after:
		return "placing cave-ins changed output_hash"
	if (bare.reactor == null) != (level.reactor == null) \
			or (bare.reactor != null and bare.reactor.to_json() != level.reactor.to_json()):
		return "the reactor changed with cave-ins"
	if bare.robots.spawns.size() != level.robots.spawns.size():
		return "the robots changed with cave-ins"
	for index: int in bare.robots.spawns.size():
		if bare.robots.spawns[index].position_mm != level.robots.spawns[index].position_mm:
			return "robot %d moved with cave-ins" % index
	if level.debris == null:
		return "" if bare.debris == null else "the debris went with cave-ins"
	var before: Array[int] = []
	if bare.debris != null:
		for index: int in bare.debris.size():
			before.append(index)
	var solid: int = 0
	while solid < before.size() and not bare.debris.is_fire(solid):
		solid += 1
	var added: int = level.debris.size() - before.size()
	for index: int in range(solid, solid + added):
		caveins.append(index)
	for index: int in before.size():
		var at: int = index if index < solid else index + added
		if not _same(bare.debris, index, level.debris, at):
			return "entry %d changed with cave-ins (now %d)" % [index, at]
	for index: int in caveins:
		if not level.debris.is_box(index) or level.debris.is_fire(index):
			return "entry %d after the solid entries is not a cave-in" % index
	return ""


func _same(a: MeltdownDebris, i: int, b: MeltdownDebris, j: int) -> bool:
	return a.positions_mm[i] == b.positions_mm[j] and a.radii_mm[i] == b.radii_mm[j] \
			and a.is_box(i) == b.is_box(j) and a.box_size(i) == b.box_size(j) \
			and a.after_ticks[i] == b.after_ticks[j] and a.is_fire(i) == b.is_fire(j) \
			and (not a.is_fire(i) or a.fire_milli_dps[i] == b.fire_milli_dps[j])


## Each cave-in is centred in a different offered tunnel with the section's
## size, falls within the section's times and the fall limit, and keeps the
## section's distances.
func _fit(generator: MineGenerator, level: LevelDef, caveins: Array[int], plan: DebrisPlan) -> String:
	if caveins.is_empty():
		return ""
	var section: DebrisCaveins = plan.caveins
	var debris: MeltdownDebris = level.debris
	var limit: int = plan.fall_limit_ticks(level)
	var used: Array[int] = []
	for index: int in caveins:
		var tunnel: int = -1
		for placement: int in DebrisCaveins.tunnels(generator):
			if DebrisCaveins.centre_mm(generator, placement) == debris.positions_mm[index]:
				tunnel = placement
		if tunnel < 0 or used.has(tunnel):
			return "cave-in %d at %s is not in its own straight tunnel" % [index, debris.position(index)]
		used.append(tunnel)
		if debris.sizes_mm[index] != section.size_mm(generator, tunnel):
			return "cave-in %d is %s mm" % [index, debris.sizes_mm[index]]
		var ticks: int = debris.after_ticks[index]
		if ticks < mini(section.min_after_ticks, limit) or ticks > mini(section.max_after_ticks, limit):
			return "cave-in %d falls after %d ticks, outside the section or past %d" % [index, ticks, limit]
		var half: Vector3i = debris.sizes_mm[index] / 2
		var at: Vector3i = debris.positions_mm[index]
		var gap: int = section.min_start_distance_mm
		if DebrisDoors._gap_squared(at, half, level.start_position_mm) < gap * gap:
			return "cave-in %d is too close to the start" % index
		gap = section.min_reactor_distance_mm + level.reactor.radius_mm
		if DebrisDoors._gap_squared(at, half, level.reactor.position_mm) < gap * gap:
			return "cave-in %d is too close to the reactor" % index
	return ""
