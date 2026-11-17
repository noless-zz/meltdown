extends RefCounted

## Loop closing (#396, #411, GEN-5, GEN-2, ARC-2): facing open connectors get
## a straight tunnel, near-facing ones a Z, a bridge never cuts through a
## module, the same seed gives the same level, and every bridged level stays
## one piece and passes the validator.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
## Share of seeds 0..999 with a loop on the shipped data: 58 in 1,000 with
## Z bridges up to 40 m sideways (#411), up from 3 with straight ones only.
## #411 asked for 10%; even with no offset limit the rate stops at 8%, because
## most open connectors do not face each other at all (see the #411 devlog).
const MIN_LOOPED: int = 50


func _bridges(low: float, high: float, count: int, offset: float = 0.0) -> LoopBridges:
	return LoopBridges.parse_json(JSON.stringify(
			{"loop_min_m": low, "loop_max_m": high, "loop_max_count": count, "loop_max_offset_m": offset,
			"dead_end_min_open": 6, "loop_bias": 0}))


## Adds a placement to a hand-built level: one box and its open connectors.
func _place(generator: MineGenerator, low: Vector3i, high: Vector3i,
		connectors: Array[ModuleConnector]) -> void:
	var placement: ModulePlacement = ModulePlacement.new("hand_%d" % generator.placements.size())
	placement.first_box = generator.min_mm.size()
	generator.add_box(low, high)
	placement.end_box = generator.min_mm.size()
	for index: int in connectors.size():
		generator.open_connectors.append(connectors[index])
		generator.open_owner.append(Vector2i(generator.placements.size(), index))
	generator.placements.append(placement)


## Two 20 m tubes 20 m apart along z, openings facing; the first also opens
## at its far end, which stays open for the start.
func _facing_pair(gap_mm: int = 20000, shift_mm: int = 0) -> MineGenerator:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-10000, -10000, -30000), Vector3i(10000, 10000, 0), [
		ModuleConnector.new(Vector3i(0, 0, 0), "+z"),
		ModuleConnector.new(Vector3i(0, 0, -30000), "-z"),
	])
	_place(generator, Vector3i(-10000 + shift_mm, -10000, gap_mm), Vector3i(10000 + shift_mm, 10000, gap_mm + 30000), [
		ModuleConnector.new(Vector3i(shift_mm, 0, gap_mm), "-z"),
	])
	return generator


func _one_piece(boxes: Array[BoxBounds]) -> bool:
	var reached: Array[int] = [0]
	var at: int = 0
	while at < reached.size():
		for other: int in boxes.size():
			if not reached.has(other) and LevelDef.joined(boxes[reached[at]], boxes[other]):
				reached.append(other)
		at += 1
	return reached.size() == boxes.size()


func test_shipped_data_file_parses() -> String:
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	if bridges.error != "":
		return "generator.json rejected: %s" % bridges.error
	return "" if bridges.max_count >= 1 and bridges.min_gap_mm > 0 and bridges.max_gap_mm >= bridges.min_gap_mm \
			else "generator.json read as %d..%d mm, %d bridges" % [bridges.min_gap_mm, bridges.max_gap_mm, bridges.max_count]


func test_bad_data_files_are_rejected_naming_every_missing_key() -> String:
	var empty: LoopBridges = LoopBridges.parse_json("{}")
	for key: String in LoopBridges.KEYS:
		if not empty.error.contains("missing key \"%s\"" % key):
			return "empty file error \"%s\" does not name %s" % [empty.error, key]
	var cases: Dictionary[String, String] = {
		"[1]": "top level",
		"{\"loop_min_m\": 6, \"loop_max_m\": 60, \"loop_max_count\": 2, \"loop_max_offset_m\": -1, \"dead_end_min_open\": 6, \"loop_bias\": 0}": "loop_max_offset_m",
		"{\"loop_min_m\": 6, \"loop_max_m\": 60, \"loop_max_count\": 2, \"loop_max_offset_m\": \"4\", \"dead_end_min_open\": 6, \"loop_bias\": 0}": "must be a number",
		"{\"loop_min_m\": 6, \"loop_max_m\": 60, \"loop_max_count\": 2, \"loop_max_offset_m\": 4, \"dead_end_min_open\": 6, \"loop_bias\": 0, \"x\": 1}": "unknown key",
		"{\"loop_min_m\": 0, \"loop_max_m\": 60, \"loop_max_count\": 2, \"loop_max_offset_m\": 4, \"dead_end_min_open\": 6, \"loop_bias\": 0}": "loop_min_m",
		"{\"loop_min_m\": 6, \"loop_max_m\": 5, \"loop_max_count\": 2, \"loop_max_offset_m\": 4, \"dead_end_min_open\": 6, \"loop_bias\": 0}": "loop_max_m",
		"{\"loop_min_m\": 6, \"loop_max_m\": 60, \"loop_max_count\": 1.5, \"loop_max_offset_m\": 4, \"dead_end_min_open\": 6, \"loop_bias\": 0}": "loop_max_count",
		"{\"loop_min_m\": \"6\", \"loop_max_m\": 60, \"loop_max_count\": 2, \"loop_max_offset_m\": 4, \"dead_end_min_open\": 6, \"loop_bias\": 0}": "must be a number",
	}
	for text: String in cases:
		var read: LoopBridges = LoopBridges.parse_json(text)
		if not read.error.contains(cases[text]):
			return "%s gave error \"%s\", expected it to mention %s" % [text, read.error, cases[text]]
	return ""


func test_facing_open_connectors_get_one_bridge() -> String:
	var generator: MineGenerator = _facing_pair()
	var boxes_before: int = generator.min_mm.size()
	var made: int = _bridges(6, 60, 2).apply(generator)
	if made != 1:
		return "%d bridges made, expected 1" % made
	if generator.min_mm.size() != boxes_before + 3:
		return "%d boxes added, expected a tunnel and two doorways" % (generator.min_mm.size() - boxes_before)
	var tunnel: int = boxes_before
	if generator.min_mm[tunnel] != Vector3i(-4000, -4000, 0) or generator.max_mm[tunnel] != Vector3i(4000, 4000, 20000):
		return "tunnel is %s..%s" % [generator.min_mm[tunnel], generator.max_mm[tunnel]]
	if generator.open_connectors.size() != 1 or generator.open_connectors[0].axis_name != "-z":
		return "%d open connectors left, expected the far end only" % generator.open_connectors.size()
	if generator.open_owner[0] != Vector2i(0, 1):
		return "open owner left is %s" % generator.open_owner[0]
	return "" if _one_piece(generator.union.boxes) else "the bridged level is not one piece"


func test_bridge_through_a_third_module_is_not_made() -> String:
	var generator: MineGenerator = _facing_pair()
	# A slab across the gap, with its own opening pointing away.
	_place(generator, Vector3i(-20000, -20000, 8000), Vector3i(20000, 20000, 12000), [
		ModuleConnector.new(Vector3i(20000, 0, 10000), "+x"),
	])
	var made: int = _bridges(6, 60, 2).apply(generator)
	if made != 0:
		return "%d bridges cut through the slab" % made
	return "" if generator.open_connectors.size() == 4 else "%d connectors open, expected 4" % generator.open_connectors.size()


func test_out_of_range_offset_or_capped_pairs_are_not_bridged() -> String:
	if _bridges(25, 60, 2).apply(_facing_pair()) != 0:
		return "a 20 m gap was bridged under a 25 m minimum"
	if _bridges(6, 15, 2).apply(_facing_pair()) != 0:
		return "a 20 m gap was bridged over a 15 m maximum"
	if _bridges(6, 60, 0).apply(_facing_pair()) != 0:
		return "a bridge was made with loop_max_count 0"
	if _bridges(6, 60, 2).apply(_facing_pair(20000, 1)) != 0:
		return "openings 1 mm off one line were bridged"
	return ""


func test_last_open_connector_is_kept_for_the_start() -> String:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-10000, -10000, -30000), Vector3i(10000, 10000, 0),
			[ModuleConnector.new(Vector3i(0, 0, 0), "+z")])
	_place(generator, Vector3i(-10000, -10000, 20000), Vector3i(10000, 10000, 50000),
			[ModuleConnector.new(Vector3i(0, 0, 20000), "-z")])
	var made: int = _bridges(6, 60, 2).apply(generator)
	return "" if made == 0 and generator.open_connectors.size() == 2 \
			else "the only two open connectors were bridged, leaving no start"


func test_same_seed_twice_gives_the_same_bridged_level() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	for level_seed: int in SEEDS:
		var first: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)
		if first.loops == 0:
			continue
		var second: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)
		if first.output_hash() != second.output_hash() or first.loops != second.loops:
			return "seed %d: two runs differ" % level_seed
		var tree: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT)
		if tree.output_hash() == first.output_hash():
			return "seed %d: the bridge did not change output_hash" % level_seed
		return ""
	return "no seed in 0..%d has a loop" % (SEEDS - 1)


func test_seeds_loop_stay_one_piece_and_pass_the_validator() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var looped: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules, SeedSweep.MODULE_COUNT, bridges)
		if generator.loops > bridges.max_count:
			return "seed %d: %d loops, above %d" % [level_seed, generator.loops, bridges.max_count]
		if generator.loops > 0:
			looped += 1
			if not _one_piece(generator.union.boxes):
				return "seed %d: the bridged level is not one piece" % level_seed
	if looped < MIN_LOOPED:
		return "%d of %d seeds have a loop, expected at least %d" % [looped, SEEDS, MIN_LOOPED]
	# SeedSweep builds every level with the shipped loops and runs LevelValidator.
	var result: Dictionary = SeedSweep.run(0, SEEDS)
	if result["looped"] != looped:
		return "the sweep found %d looped seeds, this test %d" % [result["looped"], looped]
	return "" if result["failed"] == 0 else "%d seeds failed: %s" % [result["failed"], result["failures"]]
