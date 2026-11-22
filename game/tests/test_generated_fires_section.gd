extends RefCounted

## The `fires` section of `debris.json` (#497, RUN-4, GEN-2, ARC-4): it is
## checked key by key, and the same seed places the same fires. The sweep over
## seeds 0..999 is in `test_generated_fires_sweep.gd`, which shares the
## fixtures below.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const FIRES: Dictionary = {"count": [1, 2], "radius": [2, 3], "damage_per_second": 5,
		"after_fraction": [0.05, 0.2], "min_start_distance": 15, "min_reactor_distance": 6,
		"min_robot_distance": 2}


static func debris_file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))


static func plan_of(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


## The shipped file without its fires: spheres and doors, as before #497.
func _solid_only() -> DebrisPlan:
	var data: Dictionary = debris_file()
	data.erase(DebrisPlan.FIRES_KEY)
	return plan_of(data)


static func fire_entries(debris: MeltdownDebris) -> Array[int]:
	var found: Array[int] = []
	if debris == null:
		return found
	for index: int in debris.size():
		if debris.is_fire(index):
			found.append(index)
	return found


func test_the_fires_section_reads() -> String:
	var plan: DebrisPlan = plan_of(debris_file())
	if plan.error != "" or plan.fires == null:
		return "debris.json: %s, fires %s" % [plan.error, plan.fires]
	var fires: DebrisFires = plan.fires
	if fires.min_count < 0 or fires.max_count < fires.min_count or fires.max_count < 1:
		return "fires.count %d..%d" % [fires.min_count, fires.max_count]
	var data: Dictionary = debris_file()
	data[DebrisPlan.FIRES_KEY] = FIRES.duplicate(true)
	var parsed: DebrisPlan = plan_of(data)
	if parsed.error != "":
		return "FIRES read as \"%s\"" % parsed.error
	var read: DebrisFires = parsed.fires
	if read.min_count != 1 or read.max_count != 2 or read.min_radius_mm != 2000 \
			or read.max_radius_mm != 3000 or read.milli_dps != 5000 or read.min_after_permille != 50 \
			or read.max_after_permille != 200 or read.min_start_distance_mm != 15000 \
			or read.min_reactor_distance_mm != 6000 or read.min_robot_distance_mm != 2000:
		return "FIRES read with the wrong values"
	data[DebrisPlan.FIRES_KEY]["count"] = [0, 0]
	if plan_of(data).error != "":
		return "a count of 0 was rejected: %s" % plan_of(data).error
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
	var data: Dictionary = debris_file()
	data[DebrisPlan.FIRES_KEY] = section
	var plan: DebrisPlan = plan_of(data)
	if plan.error == "":
		return "fires %s accepted" % JSON.stringify(section)
	for name: String in names:
		if not plan.error.contains(name):
			return "error \"%s\" does not name %s" % [plan.error, name]
	return ""


func test_the_same_seed_places_the_same_fires() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var data: Dictionary = debris_file()
	data[DebrisPlan.FIRES_KEY] = FIRES
	var lists: Array[String] = []
	for run: int in 2:
		var generator: MineGenerator = MineGenerator.generate(7, modules, SeedSweep.MODULE_COUNT,
				bridges)
		var level: LevelDef = generator.to_level_def(SeedSweep.load_reactor_plan(),
				SeedSweep.ship_radius(), SeedSweep.load_robot_plan(), plan_of(data))
		if level.debris == null or fire_entries(level.debris).is_empty():
			return "seed 7 got no fire"
		lists.append(level.debris.to_json())
	return "" if lists[0] == lists[1] else "seed 7 placed different debris twice"
