extends RefCounted

## Dead-end threshold as data (#421, ARC-4, GEN-1, GEN-5): `generator.json`'s
## `dead_end_min_open` sets how many open connectors a dead end needs before
## it may join. The shipped value changes no level, a lower value lets dead
## ends join earlier, and bad values are named.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
const LOW_SEEDS: int = 200


func _shipped_with(key: String, value: Variant) -> LoopBridges:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data[key] = value
	return LoopBridges.parse_json(JSON.stringify(data))


func test_shipped_value_is_six() -> String:
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	if bridges.error != "":
		return "generator.json rejected: %s" % bridges.error
	return "" if bridges.dead_end_min_open == 6 \
			else "generator.json gives dead_end_min_open %d, expected 6" % bridges.dead_end_min_open


func test_shipped_file_changes_no_level() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	# Loops off, so the only thing the file can change is the threshold: every
	# tree must match the one built with the code default.
	var settings: LoopBridges = _shipped_with("loop_max_count", 0)
	if settings.error != "":
		return "generator.json rejected: %s" % settings.error
	for level_seed: int in SEEDS:
		var from_file: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, settings)
		var from_constant: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
		if from_file.output_hash() != from_constant.output_hash():
			return "seed %d: output_hash %d with the file, %d with the constant" \
					% [level_seed, from_file.output_hash(), from_constant.output_hash()]
	return ""


func test_without_settings_the_constant_applies() -> String:
	var level: MineGenerator = MineGenerator.generate(1, SeedSweep.load_modules(), SeedSweep.MODULE_COUNT)
	var rejected: MineGenerator = MineGenerator.generate(1, SeedSweep.load_modules(), SeedSweep.MODULE_COUNT,
			_shipped_with("dead_end_min_open", 1))
	if level.dead_end_min_open != MineGenerator.DEAD_END_MIN_OPEN:
		return "no settings gave %d" % level.dead_end_min_open
	return "" if rejected.dead_end_min_open == MineGenerator.DEAD_END_MIN_OPEN \
			else "rejected settings gave %d" % rejected.dead_end_min_open


func test_value_two_lets_a_dead_end_join_with_two_open() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var catalogue: Dictionary[String, ModuleDef] = {}
	for module: ModuleDef in modules:
		catalogue[module.id] = module
	var settings: LoopBridges = _shipped_with("dead_end_min_open", 2)
	if settings.error != "" or settings.dead_end_min_open != 2:
		return "dead_end_min_open 2 read as %d, error \"%s\"" % [settings.dead_end_min_open, settings.error]
	var early: int = 0
	for level_seed: int in LOW_SEEDS:
		var level: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, settings)
		var open: int = 0
		for index: int in level.placements.size():
			var module: ModuleDef = catalogue[level.placements[index].module_id]
			if index > 0 and module.connectors.size() == 1:
				if open < 2:
					return "seed %d: dead end %d joined with %d open" % [level_seed, index, open]
				if open < MineGenerator.DEAD_END_MIN_OPEN:
					early += 1
			open += module.connectors.size() - (2 if index > 0 else 0)
	return "" if early > 0 \
			else "no dead end joined with 2..%d open in %d seeds" % [MineGenerator.DEAD_END_MIN_OPEN - 1, LOW_SEEDS]


func test_bad_values_are_rejected_naming_the_key() -> String:
	var cases: Array[Variant] = [1, 0, -3, 2.5, "6", 5000]
	for value: Variant in cases:
		var read: LoopBridges = _shipped_with("dead_end_min_open", value)
		if not read.error.contains("\"dead_end_min_open\""):
			return "dead_end_min_open %s gave error \"%s\"" % [value, read.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data.erase("dead_end_min_open")
	var missing: LoopBridges = LoopBridges.parse_json(JSON.stringify(data))
	return "" if missing.error.contains("missing key \"dead_end_min_open\"") \
			else "file without the key gave error \"%s\"" % missing.error
