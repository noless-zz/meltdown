extends RefCounted

## The minimum wall between tunnels that do not connect (#1285, GEN-1, GEN-2,
## GEN-3, ARC-2, ARC-4): `WallClearance` rejects a flush placement and the
## generator takes another, `min_wall_m` is data, the validator fails a thin
## wall, and a seed still gives the same level twice.

const SeedSweep := preload("res://tests/seed_sweep.gd")
## Seed 22 placed boxes 12 and 23 flush on z before the minimum (#1240).
const FLUSH_SEED: int = 22


func _shipped_with(key: String, value: Variant) -> LoopBridges:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data[key] = value
	return LoopBridges.parse_json(JSON.stringify(data))


## A hand-built level: a 10 m tube from z -20 to 0 with an opening at each end,
## +z at index 0 and -z at index 1, and beside the +z end a block 10 m wide
## starting `block_x_mm` along x, from z 0 to 10, with no opening.
func _tube_and_block(block_x_mm: int) -> MineGenerator:
	var generator: MineGenerator = MineGenerator.new()
	_place(generator, Vector3i(-5000, -5000, -20000), Vector3i(5000, 5000, 0), [
		ModuleConnector.new(Vector3i(0, 0, 0), "+z"),
		ModuleConnector.new(Vector3i(0, 0, -20000), "-z"),
	])
	_place(generator, Vector3i(block_x_mm, -5000, 0), Vector3i(block_x_mm + 10000, 5000, 10000), [])
	return generator


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


## A 10 m cube with an opening on +z and on -z, which the generator turns
## to join either way.
func _cube() -> ModuleDef:
	return ModuleDef.parse_json(JSON.stringify({"id": "cube",
			"boxes": [{"min": [-5.0, -5.0, -10.0], "max": [5.0, 5.0, 0.0]}],
			"connectors": [{"position": [0.0, 0.0, 0.0], "axis": "+z", "size": "small"},
					{"position": [0.0, 0.0, -10.0], "axis": "-z", "size": "small"}]}))


## The cube on the tube's +z end, from z 0 to 10, and the doorway between.
func _cube_on_top() -> Array[Vector3i]:
	return [Vector3i(-5000, -5000, 0), Vector3i(5000, 5000, 10000),
			Vector3i(-4000, -4000, -3000), Vector3i(4000, 4000, 3000)]


func test_shipped_minimum_is_one_metre() -> String:
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	if bridges.error != "":
		return "generator.json rejected: %s" % bridges.error
	if bridges.min_wall_mm != 1000:
		return "generator.json gives min_wall_mm %d, expected 1000" % bridges.min_wall_mm
	var inputs: SeedLevel = SeedLevel.load_inputs()
	return "" if is_equal_approx(inputs.validator.min_wall_m, 1.0) \
			else "the seed validator checks %s m, not the generator's 1 m" % inputs.validator.min_wall_m


func test_flush_and_thin_walls_are_rejected_one_metre_is_not() -> String:
	var cases: Array[Array] = [[5000, false, "flush"], [5999, false, "0.999 m"],
			[6000, true, "1 m"], [9000, true, "4 m"]]
	for entry: Array in cases:
		var clear: bool = WallClearance.clear(_tube_and_block(entry[0]), _cube_on_top(), 1000)
		if clear != entry[1]:
			return "%s wall: clear %s, expected %s" % [entry[2], clear, entry[1]]
	if not WallClearance.clear(_tube_and_block(5000), _cube_on_top(), 0):
		return "a minimum of 0 still rejected the flush block"
	return ""


func test_the_doorway_into_the_parent_is_an_opening_not_a_wall() -> String:
	# The cube sits flush on the tube's end; only the doorway joins them.
	var generator: MineGenerator = _tube_and_block(20000)
	if not WallClearance.clear(generator, _cube_on_top(), 1000):
		return "the cube was rejected against the tube it opens into"
	var no_door: Array[Vector3i] = [Vector3i(-5000, -5000, 0), Vector3i(5000, 5000, 10000)]
	return "" if not WallClearance.clear(generator, no_door, 1000) \
			else "the cube flush on the tube with no doorway was accepted"


func test_flush_placement_is_rejected_and_the_next_candidate_taken() -> String:
	var modules: Array[ModuleDef] = [_cube()]
	var by_id: Dictionary[String, ModuleDef] = {"cube": modules[0]}
	# Only the +z opening, beside the block: every try is flush, so none fits.
	var blocked: MineGenerator = _tube_and_block(5000)
	blocked._rng.seed = 1
	blocked.open_connectors.remove_at(1)
	blocked.open_owner.remove_at(1)
	blocked.dead_end_min_open = 0
	if blocked._place_one(modules, by_id):
		return "a placement flush against the block was accepted"
	var off: MineGenerator = _tube_and_block(5000)
	off._rng.seed = 1
	off.open_connectors.remove_at(1)
	off.open_owner.remove_at(1)
	off.min_wall_mm = 0
	if not off._place_one(modules, by_id):
		return "with a minimum of 0 the flush placement did not fit either"
	# Both openings: the generator goes on to the -z end, clear of the block.
	var level: MineGenerator = _tube_and_block(5000)
	level._rng.seed = 1
	if not level._place_one(modules, by_id):
		return "no placement was taken with the clear -z opening open"
	var placed: ModulePlacement = level.placements[level.placements.size() - 1]
	return "" if placed.parent == 0 and placed.parent_connector == 1 \
			else "placed on parent %d opening %d, expected the tube's -z end" \
			% [placed.parent, placed.parent_connector]


func test_flush_seed_now_keeps_a_metre_and_all_its_modules() -> String:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	var before: MineGenerator = MineGenerator.generate(FLUSH_SEED, inputs.modules, SeedSweep.MODULE_COUNT,
			_shipped_with("min_wall_m", 0))
	var old_gap: WallGap = WallGap.of_union(inputs.level_of(before).union)
	if old_gap.gap_m > 0.0:
		return "seed %d had a %s m wall without the minimum, expected 0" % [FLUSH_SEED, old_gap.gap_m]
	var after: MineGenerator = inputs.generate(FLUSH_SEED)
	if after.note != "":
		return "seed %d stopped short: %s" % [FLUSH_SEED, after.note]
	var gap: WallGap = WallGap.of_union(inputs.level_of(after).union)
	return "" if gap.gap_m >= 1.0 - WallClearance.TOLERANCE_M \
			else "seed %d's thinnest wall is %s m" % [FLUSH_SEED, gap.gap_m]


func test_same_seed_gives_the_same_level_twice() -> String:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	for level_seed: int in [FLUSH_SEED, 28, 32, 100]:
		var first: MineGenerator = inputs.generate(level_seed)
		var second: MineGenerator = inputs.generate(level_seed)
		if first.output_hash() != second.output_hash():
			return "seed %d gave two levels" % level_seed
	return ""


func test_validator_fails_a_wall_below_the_minimum() -> String:
	var level: LevelDef = LevelDef.new()
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-4, -2, -40), Vector3(0, 2, 0)),
			BoxBounds.new(Vector3(0.5, -2, -40), Vector3(4.5, 2, 0))]
	level.union = BoxUnion.new(boxes)
	level.start_position_mm = Vector3i(-2000, 0, -20000)
	var validator: LevelValidator = LevelValidator.new()
	var unchecked: Array[String] = validator.validate(level, 1.0, false)
	for message: String in unchecked:
		if message.begins_with(WallClearance.CHECK + ":"):
			return "a minimum of 0 failed the wall: %s" % message
	validator.min_wall_m = 1.0
	for message: String in validator.validate(level, 1.0, false):
		if message.begins_with(WallClearance.CHECK + ": boxes 0 and 1 are 0.500 m apart on x"):
			return ""
	return "no wall failure for 0.5 m of rock: %s" % [validator.validate(level, 1.0, false)]


func test_bad_minimums_are_rejected_naming_the_key() -> String:
	for value: Variant in [-1, "1", 101]:
		var read: LoopBridges = _shipped_with("min_wall_m", value)
		if not read.error.contains("\"min_wall_m\""):
			return "min_wall_m %s gave error \"%s\"" % [value, read.error]
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SeedSweep.GENERATOR_FILE))
	data.erase("min_wall_m")
	var missing: LoopBridges = LoopBridges.parse_json(JSON.stringify(data))
	return "" if missing.error.contains("missing key \"min_wall_m\"") \
			else "file without the key gave error \"%s\"" % missing.error
