extends RefCounted

## Placement biased towards loops (#438, GEN-5, GEN-1, GEN-2, ARC-4):
## `generator.json`'s `loop_bias` is read and checked with the other generator
## keys, 0 places exactly as before, and above 0 the same seed still gives the
## same level while more seeds get a loop.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
## Seeds for the slower comparisons between bias values.
const FEW_SEEDS: int = 200
## `hash()` of the 1,000 `output_hash` values of seeds 0..999 on `main` before
## #438, with the shipped `generator.json` of the time (bias did not exist,
## so it is the file with `loop_bias` 0) and with no settings at all. #472
## reshaped the Z bridges, so the pin with the file moved from 3783710171;
## levels without bridges are unchanged.
const PIN_WITH_FILE: int = 2981470496
const PIN_WITHOUT_SETTINGS: int = 3339467983
## `generator.json`'s `loop_bias` in thousandths: 0.6 gives 214 looped seeds of
## 0..999 with every level passing the validator (#438).
const SHIPPED_BIAS_PERMILLE: int = 600


func _shipped_with(key: String, value: Variant) -> LoopBridges:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data[key] = value
	return LoopBridges.parse_json(JSON.stringify(data))


func _connector(position: Vector3i, axis_name: String) -> ModuleConnector:
	return ModuleConnector.new(position, axis_name, "small")


func _looped(bridges: LoopBridges, count: int) -> int:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var looped: int = 0
	for level_seed: int in count:
		if MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges).loops > 0:
			looped += 1
	return looped


func test_shipped_value_reads_and_bad_values_are_named() -> String:
	var shipped: LoopBridges = SeedSweep.load_loop_bridges()
	if shipped.error != "":
		return "generator.json rejected: %s" % shipped.error
	# #438 ships 0.6 (about 21% looped seeds) now that #472 made nonzero
	# values pass the validator (`test_loop_z_joints.gd`).
	if shipped.loop_bias_permille != SHIPPED_BIAS_PERMILLE:
		return "shipped loop_bias read as %d thousandths, expected %d" % [shipped.loop_bias_permille, SHIPPED_BIAS_PERMILLE]
	for value: Variant in [0, 0.25, 1]:
		var read: LoopBridges = _shipped_with("loop_bias", value)
		if read.error != "" or read.loop_bias_permille != roundi(float(value) * LoopBias.SCALE):
			return "loop_bias %s read as %d, error \"%s\"" % [value, read.loop_bias_permille, read.error]
	for value: Variant in [-0.1, 1.5, "0.5", true]:
		var read: LoopBridges = _shipped_with("loop_bias", value)
		if not read.error.contains("\"loop_bias\""):
			return "loop_bias %s gave error \"%s\"" % [value, read.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data.erase("loop_bias")
	var missing: LoopBridges = LoopBridges.parse_json(JSON.stringify(data))
	return "" if missing.error.contains("missing key \"loop_bias\"") \
			else "file without the key gave error \"%s\"" % missing.error


func test_bias_zero_and_no_settings_place_exactly_as_before() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var settings: LoopBridges = _shipped_with("loop_bias", 0)
	var with_file: Array[int] = []
	var without: Array[int] = []
	for level_seed: int in SEEDS:
		with_file.append(MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, settings).output_hash())
		without.append(MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT).output_hash())
	if hash(with_file) != PIN_WITH_FILE:
		return "loop_bias 0: seeds 0..%d hash to %d, expected %d" % [SEEDS - 1, hash(with_file), PIN_WITH_FILE]
	return "" if hash(without) == PIN_WITHOUT_SETTINGS \
			else "no settings: seeds 0..%d hash to %d, expected %d" % [SEEDS - 1, hash(without), PIN_WITHOUT_SETTINGS]


func test_same_seed_twice_gives_the_same_biased_level() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = _shipped_with("loop_bias", 1)
	var unbiased: LoopBridges = _shipped_with("loop_bias", 0)
	var changed: int = 0
	for level_seed: int in FEW_SEEDS:
		var first: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)
		var second: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)
		if first.output_hash() != second.output_hash() or first.loops != second.loops:
			return "seed %d: two runs with loop_bias 1 differ" % level_seed
		if first.output_hash() != MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT,
				unbiased).output_hash():
			changed += 1
	return "" if changed > 0 else "loop_bias 1 changed none of seeds 0..%d" % (FEW_SEEDS - 1)


func test_more_bias_gives_more_loops() -> String:
	var none: int = _looped(_shipped_with("loop_bias", 0), FEW_SEEDS)
	var half: int = _looped(_shipped_with("loop_bias", 0.5), FEW_SEEDS)
	var full: int = _looped(_shipped_with("loop_bias", 1), FEW_SEEDS)
	return "" if none < half and half < full \
			else "looped seeds of %d: %d at 0, %d at 0.5, %d at 1" % [FEW_SEEDS, none, half, full]


func test_facing_needs_opposite_axes_within_gap_and_offset() -> String:
	var bridges: LoopBridges = LoopBridges.parse_json(JSON.stringify(
			{"loop_min_m": 6, "loop_max_m": 60, "loop_max_count": 2, "loop_max_offset_m": 10,
			"dead_end_min_open": 6, "loop_bias": 1}))
	if bridges.error != "":
		return "fixture rejected: %s" % bridges.error
	var from: ModuleConnector = _connector(Vector3i.ZERO, "+x")
	var cases: Array[Array] = [
		[_connector(Vector3i(20000, 0, 0), "-x"), true, "in line"],
		[_connector(Vector3i(20000, 10000, 0), "-x"), true, "10 m sideways"],
		[_connector(Vector3i(20000, 6000, 8000), "-x"), true, "10 m sideways on two axes"],
		[_connector(Vector3i(20000, 6000, 8001), "-x"), false, "1 mm past the offset"],
		[_connector(Vector3i(5999, 0, 0), "-x"), false, "closer than loop_min_m"],
		[_connector(Vector3i(60001, 0, 0), "-x"), false, "further than loop_max_m"],
		[_connector(Vector3i(-20000, 0, 0), "-x"), false, "behind, facing away"],
		[_connector(Vector3i(20000, 0, 0), "+x"), false, "the same way"],
		[_connector(Vector3i(20000, 0, 0), "-y"), false, "another axis"],
		[ModuleConnector.new(Vector3i(20000, 0, 0), "-x", "large"), false, "another size class"],
	]
	for entry: Array in cases:
		if LoopBias.faces(bridges, from, entry[0]) != entry[1]:
			return "%s: faces gave %s" % [entry[2], not entry[1]]
	return ""
