extends RefCounted

## The generator places the reactor (#356, GEN-1, GEN-2, RUN-2, ARC-4): over
## 1,000 seeds every 10-module level has a reactor in the module furthest from
## the first in joins, inside a box with the reactor's radius and a ship's
## diameter clear; the same seed puts it in the same place; a level too short
## gets none and a note; and the data file is checked key by key.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const REACTOR_FILE: String = "res://data/gen/reactor.json"
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 15000
const VALID: Dictionary = {"radius": 2.5, "hull": 400, "meltdown_seconds": 90, "min_hops": 2}


func _plan() -> ReactorPlan:
	return ReactorPlan.parse_json(FileAccess.get_file_as_string(REACTOR_FILE))


func _straight() -> Array[ModuleDef]:
	var modules: Array[ModuleDef] = []
	modules.append(ModuleDef.parse_json(FileAccess.get_file_as_string(
			SeedSweep.MODULES_DIR + "straight_tunnel.json")))
	return modules


func _rejects(data: Dictionary, names: String) -> String:
	var plan: ReactorPlan = ReactorPlan.parse_json(JSON.stringify(data))
	if plan.error == "":
		return "%s accepted" % JSON.stringify(data)
	return "" if plan.error.contains(names) else "error \"%s\" does not name %s" % [plan.error, names]


func test_data_file_reads() -> String:
	var plan: ReactorPlan = _plan()
	if plan.error != "":
		return "reactor.json: %s" % plan.error
	if plan.min_hops < 1 or plan.reactor.radius_mm != 2500 or plan.reactor.max_hull != 400.0 \
			or plan.reactor.meltdown_seconds != 90.0:
		return "read %d hops, %d mm, hull %s, %s s" % [plan.min_hops, plan.reactor.radius_mm,
				plan.reactor.max_hull, plan.reactor.meltdown_seconds]
	return ""


func test_data_file_is_rejected_naming_the_bad_key() -> String:
	var cases: Array = [
		["radius", -1, "radius"], ["hull", "lots", "hull"], ["meltdown_seconds", 0, "meltdown_seconds"],
		["min_hops", 0, "min_hops"], ["min_hops", 2.5, "min_hops"], ["position", [0, 0, 0], "position"],
		["exit_radius", 4, "exit_radius"], ["colour", "red", "colour"],
	]
	for case: Array in cases:
		var data: Dictionary = VALID.duplicate()
		data[case[0]] = case[1]
		var problem: String = _rejects(data, case[2])
		if problem != "":
			return problem
	for key: String in VALID:
		var data: Dictionary = VALID.duplicate()
		data.erase(key)
		var problem: String = _rejects(data, "\"%s\"" % key)
		if problem != "":
			return problem
	if ReactorPlan.parse_json("[]").error == "":
		return "a JSON list was accepted"
	return ""


func test_thousand_seeds_get_a_clear_reactor_in_the_furthest_module() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var plan: ReactorPlan = _plan()
	var ship_radius: float = SeedSweep.ship_radius()
	var started: int = Time.get_ticks_msec()
	for level_seed: int in range(1, SEEDS + 1):
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
		if generator.placements.size() != SeedSweep.MODULE_COUNT:
			continue
		var level: LevelDef = generator.to_level_def(plan, ship_radius)
		var problem: String = _check(generator, level, plan, ship_radius)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
	var elapsed: int = Time.get_ticks_msec() - started
	return "" if elapsed <= TIME_LIMIT_MS else "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]


func _check(generator: MineGenerator, level: LevelDef, plan: ReactorPlan, ship_radius: float) -> String:
	if level.reactor == null:
		return "no reactor: %s" % generator.reactor_note
	# Joins counted by walking up the parents, independently of the generator.
	var furthest: int = -1
	var most: int = -1
	for index: int in generator.placements.size():
		var joins: int = 0
		var at: int = index
		while generator.placements[at].parent >= 0:
			at = generator.placements[at].parent
			joins += 1
		if joins >= most:
			most = joins
			furthest = index
	if generator.reactor_placement != furthest:
		return "reactor in module %d, furthest is %d (%d joins)" % [generator.reactor_placement, furthest, most]
	var placement: ModulePlacement = generator.placements[furthest]
	var clear: float = level.reactor.radius() + 2.0 * ship_radius
	var held: bool = false
	for box: int in range(placement.first_box, placement.end_box):
		held = held or level.union.boxes[box].holds(level.reactor.position(), clear)
	if not held:
		return "reactor at %s not inside a box of module %d with %s m clear" \
				% [level.reactor.position(), furthest, clear]
	if level.reactor.hull != plan.reactor.max_hull or level.reactor.destroyed:
		return "reactor does not start at full hull"
	return ""


func test_same_seed_same_reactor_and_hash_unchanged() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var plan: ReactorPlan = _plan()
	var first: MineGenerator = MineGenerator.generate(42, modules, SeedSweep.MODULE_COUNT)
	var before: int = first.output_hash()
	var a: LevelDef = first.to_level_def(plan, 1.0)
	if first.output_hash() != before:
		return "placing the reactor changed output_hash"
	var b: LevelDef = MineGenerator.generate(42, modules, SeedSweep.MODULE_COUNT).to_level_def(plan, 1.0)
	if a.reactor == null or b.reactor == null:
		return "seed 42 has no reactor"
	if a.reactor.position_mm != b.reactor.position_mm:
		return "positions differ: %s and %s" % [a.reactor.position_mm, b.reactor.position_mm]
	return ""


func test_without_a_plan_there_is_no_reactor() -> String:
	var level: LevelDef = MineGenerator.generate(7, SeedSweep.load_modules(), SeedSweep.MODULE_COUNT).to_level_def()
	return "" if level.reactor == null else "a reactor was placed without a plan"


func test_two_module_chain_below_min_hops_gets_no_reactor_and_a_note() -> String:
	var plan: ReactorPlan = ReactorPlan.parse_json(JSON.stringify(
			{"radius": 2.5, "hull": 400, "meltdown_seconds": 90, "min_hops": 2}))
	var generator: MineGenerator = MineGenerator.generate(3, _straight(), 2)
	if generator.placements.size() != 2:
		return "%d modules placed" % generator.placements.size()
	var level: LevelDef = generator.to_level_def(plan, 1.0)
	if level.reactor != null:
		return "reactor placed one join from the first module"
	if not generator.reactor_note.contains("below 2"):
		return "note is \"%s\"" % generator.reactor_note
	return "" if generator.reactor_placement == -1 else "reactor_placement is %d" % generator.reactor_placement


func test_box_too_small_gets_no_reactor_and_a_note() -> String:
	# A 10 m tunnel holds 2.5 m plus a 2 m ship diameter (4.5 m) but not 4 m plus 2 m.
	var plan: ReactorPlan = ReactorPlan.parse_json(JSON.stringify(
			{"radius": 4, "hull": 400, "meltdown_seconds": 90, "min_hops": 1}))
	var generator: MineGenerator = MineGenerator.generate(3, _straight(), 3)
	var level: LevelDef = generator.to_level_def(plan, 1.0)
	if level.reactor != null:
		return "a 4 m reactor fit in a 10 m tunnel with a ship's diameter to spare"
	return "" if generator.reactor_note.contains("too small") else "note is \"%s\"" % generator.reactor_note
